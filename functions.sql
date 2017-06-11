----------------------------------------------------------------------
-----------WAYBILL----------------------------------------------------
----------------------------------------------------------------------

create or replace function list_waybill () returns json as $$
declare
  w json;
begin
  w := json_agg(t) from (select * from waybill order by waybill_id desc) t;
  return json_build_object('array', w);
  -- with all_waybill as (
  --   select array_agg(waybill.*) as array from waybill)
  -- select to_json(all_waybill) from all_waybill;
end; $$ language plpgsql stable;

create or replace function show_waybill (id integer) returns json as $$
declare
  waybill json;
  shipment json;
begin
  waybill := to_json(t) from (select *, (select name from supplier where supplier_id = waybill.supplier_id) as supplier_name from waybill where waybill_id = id) t;
  shipment := json_agg(t) from (select * from shipment where waybill_id = id) t;
  if waybill is null then raise exception 'Not found'; end if;
  return json_build_object('object', waybill, 'array', shipment);
end; $$ language plpgsql  stable;

create or replace function create_waybill (in input json) returns json as $$
declare
  w waybill;
  s shipment[];
  se shipment;
  id integer;
  pr integer[] default '{}';
begin
  w := json_populate_record(null::waybill, input->'waybill');
  s := array(select json_populate_recordset(null::shipment, input->'shipment'));
  perform * from waybill where waybill_id = w.waybill_id;
  if not found then
    insert into waybill
      (waybill_id, supplier_id, serial_number, original_date, return)
      values (w.waybill_id, w.supplier_id, w.serial_number, w.original_date, w.return)
      returning waybill_id into id;
  else
    update waybill set
      (supplier_id, serial_number, original_date, return) =
      (w.supplier_id, w.serial_number, w.original_date, w.return)
      where waybill_id = w.waybill_id
      returning waybill_id into id;
  end if;
  foreach se in array s loop
    pr := array_append(pr, se.product_id);
    perform * from shipment where waybill_id = id and product_id = se.product_id;
    if not found then
      insert into shipment
        (waybill_id, product_id, quantity, cost_total, sale_price)
        values (id, se.product_id, se.quantity, se.cost_total, se.sale_price);
    else
      update shipment set
        (quantity, cost_total, sale_price) =
        (se.quantity, se.cost_total, se.sale_price);
    end if;
  end loop;
  delete from shipment where waybill_id = id and not (product_id = any (pr));
  return show_waybill(id);
end; $$ language plpgsql volatile;

create or replace function delete_waybill (in id integer) returns integer as $$
declare
  output integer;
begin
  delete from waybill where waybill.waybill_id = id returning waybill_id into output;
  if not found then raise exception ''; end if;
  return output;
end; $$ language plpgsql volatile;

----------------------------------------------------------------------
-----------SUPPLIER---------------------------------------------------
----------------------------------------------------------------------

create or replace function list_supplier (input json) returns json as $$
declare
  supplier json;
  query text;
begin
  query := coalesce(input::json->>'search', '');
  supplier := json_agg(t) from (select * from supplier where name ~* query) t;
  return json_build_object('array', supplier);
end; $$ language plpgsql stable;

create or replace function show_supplier (id integer) returns json as $$
declare
  supplier json;
begin
  supplier := to_json(t) from (select * from supplier where supplier_id = id) t;
  if supplier is null then raise exception 'Not found'; end if;
  return json_build_object('object', supplier);
end; $$ language plpgsql  stable;

create or replace function create_supplier (input json) returns json as $$
declare
  s supplier;
  id integer;
begin
  s := json_populate_record(null::supplier, input->'supplier');
  s.supplier_id := nextval('supplier_supplier_id_seq');
  insert into supplier values (s.*) returning supplier_id into id;
  return show_supplier(id);
end; $$ language plpgsql volatile;

create or replace function delete_supplier (in id integer) returns integer as $$
declare
  output integer;
begin
  delete from supplier where supplier.supplier_id = id returning supplier_id into output;
  if not found then raise exception ''; end if;
  return output;
end; $$ language plpgsql volatile;

----------------------------------------------------------------------
-----------PRODUCT----------------------------------------------------
----------------------------------------------------------------------

create or replace function list_product (input json) returns json as $$
declare
  product json;
  query text;
begin
  query := coalesce(input::json->>'query', '');
  product := json_agg(t) from (select * from product where name ~* query) t;
  return json_build_object('array', product);
end; $$ language plpgsql stable;

create or replace function show_product (id integer) returns json as $$
declare
  product json;
begin
  product := to_json(t) from (select * from product where product_id = id) t;
  if product is null then raise exception 'Not found'; end if;
  return json_build_object('object', product);
end; $$ language plpgsql stable;

create or replace function create_product (input json) returns json as $$
declare
  p product;
  id integer;
begin
  p := json_populate_record(null::product, input->'product');
  p.product_id := nextval('product_product_id_seq');
  insert into product values (p.*) returning product_id into id;
  return show_product(id);
end; $$ language plpgsql volatile;

create or replace function delete_product (in id integer) returns integer as $$
declare
  output integer;
begin
  delete from product where product.product_id = id returning product_id into output;
  if not found then raise exception ''; end if;
  return output;
end; $$ language plpgsql volatile;

----------------------------------------------------------------------
-----------SHIPMENT---------------------------------------------------
----------------------------------------------------------------------

create or replace function list_shipment (in id integer) returns setof shipment as $$
  select * from shipment where waybill_id = id;
$$ language sql stable;

