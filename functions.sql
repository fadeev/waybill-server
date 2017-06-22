----------------------------------------------------------------------
-----------WAYBILL----------------------------------------------------
----------------------------------------------------------------------

create or replace function list_waybill () returns json as $$
declare
  w json;
begin
  w := json_agg(t) from (
    with sh as (
      select waybill_id, sum(cost_total) cost_total
      from shipment
      group by waybill_id
    )
    select
      w.waybill_id,
      w.serial_number,
      w.original_date,
      to_char(w.original_date, 'DD, TMMonth') original_date_day_month,
      w.return,
      sh.cost_total,
      su.name
    from waybill w
    left join sh on w.waybill_id = sh.waybill_id
    left join supplier su on w.supplier_id = su.supplier_id
    order by w.waybill_id desc
  ) t;
  return json_build_object('array', w);
end; $$ language plpgsql stable;

create or replace function show_waybill (id integer) returns json as $$
declare
  waybill json;
  shipment json;
begin
  waybill := to_json(t) from (
    select *, (select name from supplier where supplier_id = waybill.supplier_id) as supplier_name
    from waybill
    where waybill_id = id) t;
  shipment := json_agg(t) from (
    select *
    from shipment s
    join product p on s.product_id = p.product_id
    where waybill_id = id
  ) t;
  if waybill is null then raise exception 'Not found'; end if;
  return json_build_object('object', waybill, 'array', shipment);
end; $$ language plpgsql  stable;

create or replace function create_waybill (in input json) returns json as $$
declare
  w waybill;
  s shipment[];
  p product[];
  se shipment;
  pe product;
  id integer;
  pr integer[] default '{}';
begin
  w := json_populate_record(null::waybill, input->'waybill');
  s := array(select json_populate_recordset(null::shipment, input->'shipment'));
  p := array(select json_populate_recordset(null::product, input->'shipment'));
  perform * from waybill where waybill_id = w.waybill_id;
  if not found then
    insert into waybill
      (supplier_id, serial_number, original_date, return)
      values (w.supplier_id, w.serial_number, w.original_date, w.return)
      returning waybill_id into id;
  else
    update waybill set
      (supplier_id, serial_number, original_date, return) =
      (w.supplier_id, w.serial_number, w.original_date, w.return)
      where waybill_id = w.waybill_id
      returning waybill_id into id;
  end if;
  foreach pe in array p loop
    update product set name = pe.name, unit = pe.unit where product_id = pe.product_id;
  end loop;
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
        (se.quantity, se.cost_total, se.sale_price)
      where waybill_id = id and product_id = se.product_id;
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

create or replace function product_sale_price (product) returns numeric as $$
  select sale_price
  from (select * from shipment natural join waybill) s
  where s.product_id = $1.product_id
  order by s.original_date
  limit 1;
$$ language sql stable;

create or replace function product_sale_price_waybill_id (product) returns integer as $$
  select waybill_id
  from (select * from shipment natural join waybill) s
  where s.product_id = $1.product_id
  order by s.original_date
  limit 1;
$$ language sql stable;

create or replace function list_product (input json default '{}') returns json as $$
declare
  product json;
  query text;
begin
  query := coalesce(input::json->>'search', '');
  product := json_agg(t) from (
    select
      p.product_id,
      p.name,
      p.unit,
      p.product_sale_price sale_price,
      p.product_sale_price_waybill_id waybill_id
    from product p
    where name ~* query
    order by product_id
  ) t;
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
  perform * from product where product_id = p.product_id;
  if not found then
    p.product_id := nextval('product_product_id_seq');
    p.unit := coalesce(p.unit, 1);
    insert into product values (p.*) returning product_id into id;
  else
    update product
    set (name, unit) = (p.name, p.unit)
    where product_id = p.product_id
    returning product_id into id;
  end if;
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

