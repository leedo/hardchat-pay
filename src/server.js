// Generated by CoffeeScript 1.8.0
(function() {
  var alice, app, child_process, decode_dsn, decode_plack_cookie, express, fs, mysql, options, stripe;

  child_process = require("child_process");

  express = require("express");

  mysql = require("mysql");

  fs = require("fs");

  options = require("cli").parse({
    "catlady": ["c", "catlady config file", "string"],
    "stripe": ["s", "stripe secret file", "string"],
    "root": ["s", "root path", "string", "/"]
  });

  ["catlady", "stripe"].forEach(function(opt) {
    if (options[opt] === null) {
      console.error(opt + " is required");
      return process.exit(1);
    }
  });

  decode_dsn = function(value) {
    var match, opts, type;
    match = value.match(/DBI:([^:]+):(.+)/i);
    if (match) {
      type = match[1];
      opts = {};
      match[2].split(";").forEach(function(opt) {
        var kv;
        kv = opt.split("=");
        return opts[kv[0]] = kv[1];
      });
      return opts;
    }
    return {};
  };

  (function() {
    options.stripe = JSON.parse(fs.readFileSync(options.stripe));
    options.catlady = JSON.parse(fs.readFileSync(options.catlady));
    return options.catlady.dsn = decode_dsn(options.catlady.dsn);
  })();

  stripe = require("stripe")(options.stripe.sec);

  alice = mysql.createPool({
    host: options.catlady.dsn.host,
    user: options.catlady.db_user,
    password: options.catlady.db_pass,
    database: options.catlady.dsn.dbname
  });

  app = express();

  app.use(require("body-parser").urlencoded({
    extended: false
  }));

  app.use(require("cookie-parser")());

  app.use(options.root + "static", express["static"]("public", {
    extensions: ["css", "js"]
  }));

  app.set('views', './views');

  app.set('view engine', 'jade');

  app.use(function(req, res, next) {
    if (!req.cookies[options.catlady.cookie]) {
      return res.redirect("/login?dest=" + options.root);
    }
    return decode_plack_cookie(req.cookies[options.catlady.cookie], function(err, decoded) {
      if (err) {
        return res.status(400).send("Unable to decode cookie");
      }
      if (!decoded.userid) {
        return res.redirect("/login?dest=" + options.root);
      }
      return alice.getConnection(function(err, connection) {
        return connection.query("SELECT * FROM users WHERE id = ?", [decoded.userid], function(err, rows) {
          if (err || !rows.length) {
            return res.status(400).send("Invalid catlady session");
          } else {
            req["alice"] = rows[0];
            req["customer"] = false;
            if (req.alice.stripe_id) {
              return stripe.customers.retrieve(req.alice.stripe_id, function(err, customer) {
                if (!err && !customer.deleted) {
                  req["customer"] = customer;
                }
                return next();
              });
            } else {
              return next();
            }
          }
        });
      });
    });
  });

  app.get(options.root, function(req, res) {
    return stripe.plans.retrieve(options.stripe.plan, function(err, plan) {
      if (err) {
        return res.status(400).send("Invalid plan");
      }
      return res.render("index", {
        root: options.root,
        plan: plan,
        stripe: options.stripe,
        customer: req.customer,
        alice: req.alice
      });
    });
  });

  app.post(options.root + "customer", function(req, res) {
    var email, token;
    token = req.body.stripeToken;
    email = req.body.stripeEmail;
    return stripe.customers.create({
      card: token,
      plan: options.stripe.plan,
      email: email
    }, function(err, customer) {
      if (err) {
        return res.status(400).send("Unable to create customer");
      }
      return alice.getConnection(function(err, connection) {
        return connection.query("UPDATE users SET stripe_id = ? WHERE id = ?", [customer.id, req.alice.id], function(err, rows) {
          if (err) {
            return res.status(400).send("Unable to enable subscription in catlady");
          }
          return res.redirect(options.root);
        });
      });
    });
  });

  app.post(options.root + "unsubscribe/:subid", function(req, res) {
    var sub_id;
    sub_id = req.params["subid"];
    return stripe.customers.cancelSubscription(req.customer.id, sub_id, function(err, confirmation) {
      if (err) {
        return res.status(400).send("Unable to cancel subscription");
      }
      return res.redirect(options.root);
    });
  });

  app.post(options.root + "subscribe/:planid", function(req, res) {
    var plan_id;
    plan_id = req.params["planid"];
    return stripe.customers.createSubscription(req.customer.id, {
      plan: plan_id
    }, function(err, subscription) {
      if (err) {
        console.log(err);
        return res.status(400).send("Unable to create subscription");
      }
      return res.redirect(options.root);
    });
  });

  app.listen(3000);

  decode_plack_cookie = function(value, cb) {
    var cookie, decode, decoded, perl, sig, time, _ref;
    _ref = value.split(":"), time = _ref[0], cookie = _ref[1], sig = _ref[2];
    decode = 'print JSON::encode_json Storable::thaw MIME::Base64::decode $ARGV[0]';
    perl = child_process.spawn("perl", ["-MStorable", "-MMIME::Base64", "-MJSON", "-e", decode, cookie]);
    decoded = {};
    perl.stdout.on("data", function(data) {
      return decoded = JSON.parse(data);
    });
    return perl.on("close", function(code) {
      return cb(null, decoded);
    });
  };

}).call(this);
