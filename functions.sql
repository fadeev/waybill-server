----------------------------------------------------------------------
-----------WAYBILL----------------------------------------------------
----------------------------------------------------------------------

create or replace function list_waybill (in input json) returns json as $$
declare
  w json;
begin
  w := json_agg(t) from (
    with sh as (
      select waybill_id, sum(cost_total) cost_total
      from shipment
      group by waybill_id
    ), payment as (
      select waybill_id, sum(amount) payment_amount
      from payment
      group by waybill_id
    )
    select
      w.waybill_id,
      w.serial_number,
      w.original_date,
      to_char(w.original_date, 'DD, TMMonth') original_date_day_month,
      w.return,
      sh.cost_total,
      su.name,
      su.supplier_id,
      se.organization_id sender_id,
      se.name sender_name,
      re.organization_id receiver_id,
      re.name receiver_name,
      payment.payment_amount
    from waybill w
    left join sh on w.waybill_id = sh.waybill_id
    left join payment on w.waybill_id = payment.waybill_id
    left join supplier su on w.supplier_id = su.supplier_id
    left join organization se on w.sender_id = se.organization_id
    left join organization re on w.receiver_id = re.organization_id
    order by w.original_date desc
  ) t;
  return json_build_object('waybill', w);
end; $$ language plpgsql stable;

create or replace function show_waybill (id integer) returns json as $$
declare
  waybill json;
  shipment json;
  payment json;
begin
  waybill := to_json(t) from (
    select
      *,
      (select name from supplier where supplier_id = waybill.supplier_id) as supplier_name,
      (select name from organization where organization_id = waybill.sender_id) as sender_name,
      (select name from organization where organization_id = waybill.receiver_id) as receiver_name
    from waybill
    where waybill_id = id) t;
  shipment := json_agg(t) from (
    select *
    from shipment s
    join product p on s.product_id = p.product_id
    where waybill_id = id
  ) t;
  payment := json_agg(t) from (
    select * from payment where waybill_id = id
  ) t;
  if waybill is null then raise exception 'Not found'; end if;
  return json_build_object('waybill', waybill, 'shipment', shipment, 'payment', payment);
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
      (supplier_id, serial_number, original_date, return, sender_id, receiver_id)
      values (w.supplier_id, w.serial_number, w.original_date, w.return, w.sender_id, w.receiver_id)
      returning waybill_id into id;
  else
    update waybill set
      (supplier_id, serial_number, original_date, return, sender_id, receiver_id) =
      (w.supplier_id, w.serial_number, w.original_date, w.return, w.sender_id, w.receiver_id)
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
  return json_build_object('supplier', supplier);
end; $$ language plpgsql stable;

create or replace function show_supplier (id integer) returns json as $$
declare
  supplier json;
begin
  supplier := to_json(t) from (select * from supplier where supplier_id = id) t;
  if supplier is null then raise exception 'Not found'; end if;
  return json_build_object('supplier', supplier);
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
  select sale_price from (
    select sale_price, s.original_date as date
    from (select * from shipment natural join waybill) s
    where s.product_id = $1.product_id
    union
    select sale_price, created_at as date
    from inventory
    where product_id = $1.product_id
  ) t
  order by date desc
  limit 1;
$$ language sql stable;

create or replace function product_quantity (product) returns numeric as $$
declare
  quant numeric;
  inv inventory;
  invent numeric default 0;
  incoming numeric default 0;
  outgoing numeric default 0;
  sales numeric default 0;
begin
  select * from inventory where product_id = $1.product_id order by created_at desc limit 1 into inv;

  select sum(s.quantity)
  from shipment s
  left join waybill w on s.waybill_id = w.waybill_id
  where return is not true
  and product_id = $1.product_id
  and original_date > coalesce(inv.created_at, '0001-01-01') into incoming;

  select sum(s.quantity)
  from shipment s
  left join waybill w on s.waybill_id = w.waybill_id
  where return is true
  and product_id = $1.product_id
  and original_date > coalesce(inv.created_at, '0001-01-01') into outgoing;

  select sum(quantity)
  from sale_item
  left join sale on sale.sale_id = sale_item.sale_id
  where product_id = $1.product_id
  and created_at > coalesce(inv.created_at, '0001-01-01') into sales;

  return coalesce(inv.quantity, 0) + coalesce(incoming, 0) - coalesce(outgoing, 0) - coalesce(sales, 0);
end; $$ language plpgsql stable;

create or replace function product_sale_price_waybill_id (product) returns integer as $$
  select waybill_id
  from (select * from shipment natural join waybill) s
  where s.product_id = $1.product_id
  order by s.original_date asc
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
      p.product_quantity stock_quantity,
      p.product_sale_price sale_price,
      p.product_sale_price_waybill_id waybill_id
    from product p
    where name ~* query
    order by product_id desc
  ) t;
  return json_build_object('product', product);
end; $$ language plpgsql stable;

create or replace function show_product (id integer) returns json as $$
declare
  product json;
  shipment json;
  inventory json;
  content json;
begin
  product := to_json(t) from (select * from product where product_id = id) t;
  if product is null then raise exception 'Not found'; end if;
  content := json_agg(t) from (
    select
      p.name as name,
      pc.quantity as quantity,
      pc.content_id as product_id
    from product_content pc
    left join product p on pc.content_id = p.product_id
    where pc.product_id = id
  ) t;
  shipment := json_agg(t) from (select * from shipment s left join waybill w on s.waybill_id = w.waybill_id where product_id = id) t;
  inventory := json_agg(t) from (select * from inventory where product_id = id) t;
  return json_build_object('product', product, 'shipment', shipment, 'inventory', inventory, 'content', content);
end; $$ language plpgsql stable;

create or replace function create_product (input json) returns json as $$
declare
  p product;
  id integer;
  s product_content[];
  g product_content;
begin
  p := json_populate_record(null::product, input->'product');
  perform * from product where product_id = p.product_id;
  if not found then
    p.product_id := nextval('product_product_id_seq');
    p.unit := coalesce(p.unit, 1);
    insert into product values (p.*) returning product_id into id;
    s := array(select json_populate_recordset(null::product_content, input#>'{product,content}'));
    foreach g in array s loop
      insert into product_content
      (product_id, content_id, quantity) values
      (id, g.product_id, g.quantity);
    end loop;
  else
    update product
    set (name, unit) = (p.name, p.unit)
    where product_id = p.product_id
    returning product_id into id;
    delete from product_content where product_id = id;
    s := array(select json_populate_recordset(null::product_content, input#>'{product,content}'));
    foreach g in array s loop
      insert into product_content
      (product_id, content_id, quantity) values
      (id, g.product_id, g.quantity);
    end loop;
  end if;
  return show_product(id);
end; $$ language plpgsql volatile;

create or replace function delete_product (in id integer) returns integer as $$
declare
  output integer;
begin
  delete from product_content where product_id = id;
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

----------------------------------------------------------------------
-----------SALE-------------------------------------------------------
----------------------------------------------------------------------

create or replace function list_sale (in input json) returns json as $$
declare
  s json;
  d text;
begin
  d := input->>'date';
  s := json_agg(t) from (
    with sale_item_by_id as (
      select sale_id, array_agg(t) sale_item, sum(quantity * sale_price) sum from (
        select * from sale_item si left join product p on si.product_id = p.product_id
      ) t
      group by sale_id
    )
    select *
    from sale left join sale_item_by_id on sale.sale_id = sale_item_by_id.sale_id
    where to_char(sale.created_at, 'YYYY-MM-DD') = d
    order by created_at desc
  ) t;
  return json_build_object('sale', s);
end; $$ language plpgsql stable;

create or replace function create_sale (in input json) returns json as $$
declare
  si sale_item[];
  id integer;
  sie sale_item;
  sale_item json;
begin
  si := array(select json_populate_recordset(null::sale_item, input->'sale_item'));
  insert into sale default values returning sale_id into id;
  foreach sie in array si loop
    insert into sale_item
    (sale_id, product_id, quantity, sale_price) values
    (id, sie.product_id, sie.quantity, sie.sale_price);
  end loop;
  sale_item := json_agg(t) from (
    select * from sale_item where sale_id = id
  ) t;
  return json_build_object('sale_item', sale_item);
end; $$ language plpgsql volatile;

----------------------------------------------------------------------
-----------REVENUE----------------------------------------------------
----------------------------------------------------------------------

create or replace function list_revenue (in input json) returns json as $$
declare
  s json;
begin
  s := json_agg(t) from (
    with sale_list as (
      select sale_id, sum(quantity*sale_price)
      from sale_item
      group by sale_id
    )
    select
      yyyymmdd,
      to_char(yyyymmdd::date, 'MM') mm,
      to_char(yyyymmdd::date, 'TMMonth') tmm,
      to_char(yyyymmdd::date, 'DD') dd,
      sum(sum)
    from (
      select
        to_char(created_at, 'YYYY-MM-DD') yyyymmdd,
        sum
      from sale s
      join sale_list sl
      on s.sale_id = sl.sale_id
    ) t1
    group by yyyymmdd
  ) t;
  return json_build_object('revenue', s);
end; $$ language plpgsql stable;

----------------------------------------------------------------------
-----------ORGANIZATION-----------------------------------------------
----------------------------------------------------------------------

create or replace function list_organization (in input json) returns json as $$
declare
  organization_array json;
  query text;
begin
  query := coalesce(input::json->>'search', '');
  organization_array := json_agg(t) from (
    select
      o.organization_id,
      o.name
    from organization o
    where o.name ~* query
  ) t;
  return json_build_object('organization', organization_array);
end; $$ language plpgsql stable;

create or replace function create_organization (in input json) returns json as $$
declare
  organization_object json;
  id integer;
begin
  insert into organization
    (name) values
    (input#>>'{organization,name}')
    returning organization_id into id;
  organization_object := to_json(t) from (
    select
      o.organization_id,
      o.name
    from organization o
    where o.organization_id = id
  ) t;
  if organization_object is null then raise exception 'Not found'; end if;
  return json_build_object('organization', organization_object);
end; $$ language plpgsql stable;

create or replace function show_organization (id integer) returns json as $$
declare
  organization json;
begin
  organization := to_json(t) from (select * from organization where organization_id = id) t;
  if organization is null then raise exception 'Not found'; end if;
  return json_build_object('organization', organization);
end; $$ language plpgsql  stable;

create or replace function create_organization (input json) returns json as $$
declare
  o organization;
  id integer;
begin
  o := json_populate_record(null::organization, input->'organization');
  insert into organization (name) values (o.name) returning organization_id into id;
  return show_organization(id);
end; $$ language plpgsql volatile;

----------------------------------------------------------------------
-----------INVENTORY--------------------------------------------------
----------------------------------------------------------------------

create or replace function create_inventory (in input json) returns void as $$
declare
  si inventory[];
  sie inventory;
  d date;
begin
  si := array(select json_populate_recordset(null::inventory, input->'inventory'));
  d := input->>'date';
  foreach sie in array si loop
    insert into inventory
    (product_id, quantity, sale_price, created_at) values
    (sie.product_id, sie.quantity, sie.sale_price, d);
  end loop;
end; $$ language plpgsql volatile;

----------------------------------------------------------------------
-----------PAYMENT----------------------------------------------------
----------------------------------------------------------------------

create or replace function list_payment(in input json) returns json as $$
declare
  payment json;
  id integer;
begin
  id := input->>'id';
  payment := json_agg(t) from (
    select * from payment where waybill_id = id
  ) t;
  return json_build_object('payment', payment);
end; $$ language plpgsql stable;

create or replace function delete_payment (in id integer) returns integer as $$
declare
  output integer;
begin
  delete from payment where payment.payment_id = id returning payment_id into output;
  if not found then raise exception ''; end if;
  return output;
end; $$ language plpgsql volatile;

create or replace function show_payment (id integer) returns json as $$
declare
  payment json;
begin
  payment := to_json(t) from (select * from payment where payment_id = id) t;
  if payment is null then raise exception 'Not found'; end if;
  return json_build_object('payment', payment);
end; $$ language plpgsql stable;

create or replace function create_payment (in input json) returns json as $$
declare
  p payment;
  id integer;
begin
  p := json_populate_record(null::payment, input->'payment');
  insert into payment
    (waybill_id, amount, created_at, method) values
    (p.waybill_id, p.amount, p.created_at, p.method)
    returning payment_id into id;
  return show_payment(id);
end; $$ language plpgsql volatile;