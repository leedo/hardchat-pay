child_process = require "child_process"
express = require "express"
mysql = require "mysql"
fs = require "fs"

options = require("cli").parse
  "catlady": ["c", "catlady config file", "string"],
  "stripe": ["s", "stripe secret file", "string"],
  "root": ["s", "root path", "string", "/"]

["catlady", "stripe"].forEach (opt) ->
  if options[opt] is null
    console.error opt + " is required"
    process.exit 1

decode_dsn = (value) ->
  match = value.match(/DBI:([^:]+):(.+)/i)
  if (match)
    type = match[1]
    opts = {}
    match[2].split(";").forEach (opt) ->
      kv = opt.split("=")
      opts[kv[0]] = kv[1]
    return opts
  return {}

do ->
  options.stripe = JSON.parse fs.readFileSync options.stripe
  options.catlady = JSON.parse fs.readFileSync options.catlady
  options.catlady.dsn = decode_dsn options.catlady.dsn

stripe = require("stripe")(options.stripe.sec)
alice = mysql.createPool
  host: options.catlady.dsn.host,
  user: options.catlady.db_user,
  password: options.catlady.db_pass,
  database: options.catlady.dsn.dbname

app = express()
app.use require("body-parser").urlencoded {extended: false}
app.use require("cookie-parser")()
app.use options.root + "static", express.static("public", {extensions: ["css", "js"]})
app.set 'views', './views'
app.set 'view engine', 'jade'

# make sure they're logged into catlady
app.use (req, res, next) ->
  if !req.cookies[options.catlady.cookie]
    return res.redirect "/login?dest=" + options.root

  decode_plack_cookie req.cookies[options.catlady.cookie], (err, decoded) ->
    if err
      return res.status(400).send "Unable to decode cookie"
    if !decoded.userid
      return res.redirect "/login?dest=" + options.root

    alice.getConnection (err, connection) ->
      connection.query "SELECT * FROM users WHERE id = ?", [decoded.userid], (err, rows) ->
        if err || !rows.length
          res.status(400).send "Invalid catlady session"
        else
          req["alice"] = rows[0]
          req["customer"] = false
          if req.alice.stripe_id
            stripe.customers.retrieve req.alice.stripe_id, (err, customer) ->
              if (!err and !customer.deleted)
                req["customer"] = customer
              next()
          else
            next()

app.get options.root, (req, res) ->
  stripe.plans.retrieve options.stripe.plan, (err, plan) ->
    if err
      return res.status(400).send "Invalid plan"
    res.render "index", {
      root: options.root,
      plan: plan,
      stripe: options.stripe,
      customer: req.customer,
      alice: req.alice
    }

app.post options.root + "customer", (req, res) ->
  token = req.body.stripeToken
  email = req.body.stripeEmail
  stripe.customers.create {
    card: token,
    plan: options.stripe.plan,
    email: email,
  }, (err, customer) ->
    if err
      return res.status(400).send "Unable to create customer"
    alice.getConnection (err, connection) ->
      connection.query "UPDATE users SET stripe_id = ? WHERE id = ?", [customer.id, req.alice.id], (err, rows) ->
        if err
          return res.status(400).send "Unable to enable subscription in catlady"
        res.redirect options.root

app.post options.root + "unsubscribe/:subid", (req, res) ->
  sub_id = req.params["subid"]
  stripe.customers.cancelSubscription req.customer.id, sub_id, (err, confirmation) ->
    if err
      return res.status(400).send "Unable to cancel subscription"
    res.redirect options.root

app.post options.root + "subscribe/:planid", (req, res) ->
  plan_id = req.params["planid"]
  stripe.customers.createSubscription req.customer.id, {plan: plan_id}, (err, subscription) ->
    if err
      console.log err
      return res.status(400).send "Unable to create subscription"
    res.redirect options.root

app.listen 3000

# TODO: verify cookie integrity with plack session secret
decode_plack_cookie  = (value, cb) ->
  [time, cookie, sig] = value.split(":")
  decode = 'print JSON::encode_json Storable::thaw MIME::Base64::decode $ARGV[0]'
  perl = child_process.spawn "perl", ["-MStorable", "-MMIME::Base64", "-MJSON", "-e", decode, cookie]
  decoded = {}
  perl.stdout.on "data", (data) ->
    decoded = JSON.parse data
  perl.on "close", (code) ->
    cb(null, decoded)
