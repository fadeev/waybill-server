begin;

create table supplier (
       supplier_id serial primary key,
       name text
);

create table waybill (
       waybill_id serial primary key,
       supplier_id integer references supplier,
       created_at timestamp default now(),
       serial_number text,
       original_date date,
       return boolean
);

create table product (
       product_id serial primary key,
       name text,
       unit integer default 0
);

create table shipment (
       shipment_id serial primary key,
       waybill_id integer references waybill on delete cascade,
       product_id integer not null references product,
       quantity numeric,
       cost_total numeric,
       sale_price numeric
);

create table sale (
       sale_id serial primary key,
       created_at timestamp default now()
);

create table sale_item (
       sale_item_id serial primary key,
       sale_id integer references sale,
       product_id integer references product,
       quantity numeric,
       sale_price numeric
);

create table inventory (
       inventory_id serial primary key,
       product_id integer references product,
       created_at timestamp default now(),
       quantity numeric,
       sale_price numeric
);

commit;
