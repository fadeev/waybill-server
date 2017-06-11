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

app.route('/waybill')
   .get((req, res) => {
     db.one(`select * from list_waybill() as "json"`)
       .then(({json}) => res.send({data: {waybill: json.array}}))
       .catch(error => res.status(500).send(error))
   })
   .post((req, res) => {
    db.one(`select * from create_waybill($1) as "json"`, [req.body])
      .then(({json}) => res.send({data: {waybill: json.object, shipment: json.array}}))
      .catch(error => res.status(500).send(error))
   })
   .patch((req, res) => {
     res.send('Waybill PATCH')
   })

app.route('/waybill/:id')
   .get((req, res) => {
     db.one(`select * from show_waybill($1) as "json"`, [req.params.id])
       .then(({json}) => res.send({data: {waybill: json.object, shipment: json.array}}))
       .catch(error => res.status(404).send(error))
   })
   .delete((req, res) => {
     db.one(`select * from delete_waybill($1) as "waybill_id"`, [req.params.id])
       .then(waybill_id => res.send({data: {waybill: waybill_id}}))
       .catch(error => res.status(404).send())
   })

app.route('/supplier')
   .get((req, res) => {
     db.one(`select * from list_supplier($1) as "json"`, [req.query])
       .then(({json}) => res.send({data: {supplier: json.array}}))
       .catch(error => res.status(500).send())
   })
  .post((req, res) => {
    db.one(`select * from create_supplier($1) as "json"`, [req.body])
      .then(({json}) => res.send({data: {supplier: json.object}}))
      .catch(error => res.status(500).send())
  })

app.route('/supplier/:id')
   .get((req, res) => {
     db.one(`select * from show_supplier($1) as "json"`, [req.params.id])
       .then(({json}) => res.send({data: {supplier: json.object}}))
       .catch(error => res.status(404).send())
   })
   .delete((req, res) => {
     db.one(`select * from delete_supplier($1) as "supplier_id"`, [req.params.id])
       .then(supplier_id => res.send({data: {supplier: supplier_id}}))
       .catch(error => res.status(404).send())
   })

app.route('/product')
   .get((req, res) => {
     db.one(`select * from list_product($1) as "json"`, [req.query])
       .then(({json}) => res.send({data: {product: json.array}}))
       .catch(error => res.status(500).send(error))
   })
  .post((req, res) => {
    db.one(`select * from create_product($1) as "json"`, [req.body])
      .then(({json}) => res.send({data: {product: json.object}}))
      .catch(error => res.status(500).send(error))
  })

app.route('/product/:id')
   .get((req, res) => {
     db.one(`select * from show_product($1) as "json"`, [req.params.id])
       .then(({json}) => res.send({data: {product: json.object}}))
       .catch(error => res.status(404).send(error))
   })
   .delete((req, res) => {
     db.one(`select * from delete_product($1) as "product_id"`, [req.params.id])
       .then(product_id => res.send({data: {product: product_id}}))
       .catch(error => res.status(404).send(error))
   })

app.listen(3000, () => {})

module.exports = app;