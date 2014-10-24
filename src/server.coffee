express = require "express"
fs = require "fs"
child_process = require "child_process"

options = require("cli").parse
  "catlady": ["c", "catlady config file", "string"],
  "stripe": ["s", "stripe secret file", "string"]

["catlady", "stripe"].forEach (opt) ->
  if options[opt] is null
    console.error opt + " is required"
    process.exit 1

do ->
  contents = fs.readFileSync options.stripe
  options.stripe = JSON.parse contents
  contents = fs.readFileSync options.catlady
  options.catlady = JSON.parse contents

stripe = require("stripe")(options.stripe.sec)

app = express()
app.use require("body-parser").urlencoded {extended: false}
app.use require("cookie-parser")()
app.set 'views', './views'
app.set 'view engine', 'jade'

# make sure they're logged into catlady
app.use (req, res, next) ->
  if !req.cookies[options.catlady.cookie]
    return res.redirect "/login"

  decode_plack_cookie req.cookies[options.catlady.cookie], (err, decoded) ->
    if err
      return res.status(400).send "Unable to decode cookie"
    console.log decoded
    req["plack_cookie"] = decoded
    next()

app.get "/", (req, res) ->
  stripe.plans.retrieve options.stripe.plan, (err, plan) ->
    if err
      return res.status(400).send "Invalid plan"
    res.render "index", {plan: plan, stripe: options.stripe}

app.post "/", (req, res) ->
  token = req.body.stripeToken
  email = req.body.stripeEmail
  stripe.customers.create {
    card: token,
    plan: options.stripe.plan,
    email: email,
  }, (err, customer) ->
    if err
      console.log err
      return res.status(400).send "Unable to create customer"
    res.render "success"
    
app.listen 3000

decode_plack_cookie  = (value, cb) ->
  decode = 'print JSON::encode_json Storable::thaw MIME::Base64::decode [split ":", $ARGV[0]]->[1]'
  perl = child_process.spawn "perl", ["-MStorable", "-MMIME::Base64", "-MJSON", "-e", decode, value]
  decoded = null
  perl.stdout.on "data", (data) ->
    decoded = JSON.parse data
  perl.on "close", (code) ->
    cb(null, decoded)
