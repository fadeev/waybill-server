var app = require('express')();
var pgp = require('pg-promise')()
var bodyParser = require('body-parser');

var db = pgp('postgres://denis:fadeev@localhost/denis');

app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));
app.use((req, res, next) => {
    res.header("Access-Control-Allow-Methods", "GET, POST, OPTIONS, PUT, PATCH, DELETE");
    res.header("Access-Control-Allow-Origin", "*");
    res.header("Access-Control-Allow-Headers", "Origin, X-Requested-With, Content-Type, Accept");
    next();
});

app.route('/:resource')
   .get((req, res) => {
     db.one(`select * from list_${req.params.resource}($1) as "json"`, [req.query])
       .then(({json}) => res.send({data: json}))
       .catch(error => res.status(500).send(error))
   })
   .post((req, res) => {
    db.one(`select * from create_${req.params.resource}($1) as "json"`, [req.body])
      .then(({json}) => res.send({data: json}))
      .catch(error => res.status(500).send(error))
   })

app.route('/:resource/:id')
   .get((req, res) => {
     db.one(`select * from show_${req.params.resource}($1) as "json"`, [req.params.id])
       .then(({json}) => res.send({data: json}))
       .catch(error => res.status(404).send(error))
   })
   .delete((req, res) => {
     db.one(`select * from delete_${req.params.resource}($1) as "id"`, [req.params.id])
       .then(id => res.send({data: {resource: id}}))
       .catch(error => res.status(404).send(error))
   })
 
app.listen(3000, () => {})

module.exports = app;