1-
drop view if exists v_staff_performace;
create view v_staff_performance as
select
s.staff_id id,
s.first_name || ' ' || s.last_name funcionario,
ci.city || ', ' || co.country localizacao_loja,
count(distinct r.rental_id) qtd_locacoes,
coalesce(sum(p.amount),0) total_arrecadado
from staff s
join store st on st.store_id = s.store_id
join address a on a.address_id - st.address_id
join city ci on ci.city_id = a.city_id
join country co on co.country_id = ci.country_id
left join rental r on r.staff_id = s.staff_id
left join payment p on p.rental_id = r.rental_id
group by s.staff_id,s.first_name, s.last_name,ci.city,co.country

2 -

drop materialized view if exists mv_category_total_sales;
create materialized view mv_category_total_sales as select

c.category_id id,
c.name categoria,
sum(p.amount) total_receita,
from category c
join film_category fc on fc.category_id = c.category_id
join inventory i on i.film_id = fc.film_id
join rental r on r.inventory_id = i.inventory_id
join payment p on p.rental_id = r.rental_id
group by c.category_id, c.name
with data

create unique index idx_mv_category_total_sales_id
on mv_category_total_sales(id);

refresh materialized view concurrently mv_category_total_sales

3 -

create index idx_rental_em_aberto
on rental(rental_id)
where return_date is null;

select rental_id, rental_date, inventory_id, customer_id
from rental
where return_date is null;

4 -

create index idx_film_description_fts
on film
using gin (to_tsvector('english', description));

explain analyze
select filme_id, title, description
from film
where to_tsvector('english',description) @@ to_tsquery('english','documentary & drama');

set enable_seqscan = on;

5 -

create index idx_payment_customer_date
on payment(customer_id,payment_date desc);

explain analyze
select \*
from payment
where customer_id = 5
order by payment_date desc;

6 -

create index idx_customer_email_lower
on customer(lower(email));

explain analyze
select customer_id, first_name, last_name, email
from customer
where lower(email) = lower('MARY.SMITH@sakilacustomer.org');

set enable_seqscan = on;

7 -

create or replace function fn_valida_datas_rental()
returns trigger as $$
begin
if new.return_date is not null and new.return_date < new_rental_data then
raise exception 'Data de devolução (%) não pode ser anterior à data de locação (%)',
new.return_date, new.rental_date;
end if;

    return new;

end;

$$
language plpgsql;

drop trigger if exists trg_valida_datas_rental on rental;
create trigger trg_valida_datas_rental;
before insert or update on rental
for each row
execute function fn_valida_datas_rental();

8 -

drop table if exists film_cost_audit;
create table film_cost_audit(
    id serial primary key,
    film_id integer not null,
    old_cost numeric(5,2),
    new_cost numeric(5,2),
    changed_at timestamp not null default now()
);

create or replace funtion fn_audit_replacement_cost()
return trigger as
$$

begin
insert into fil_cost_audit(film_id,old_cost,new_cost,changed_at)
values(old.film_id, old.replacement_cost, new.replacement_cost,now());

    return new;

end;

$$
language plpgsql;

drop trigger if exists trg_audit_replacement_cost on film;
create trigger trg_audit_replacement_cost
after update on film
for each row
when(old.replacement_cost is distinct from new.replacement_cost)
execute function fn_audit_replacement_cost();

9 -




$$
