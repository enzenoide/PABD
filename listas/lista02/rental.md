# LISTA DE EXERCÍCIOS — Banco Sakila (PostgreSQL)

---

## Questão 01 - View de Performance da Equipe

A gerência quer um painel rápido para avaliar o desempenho dos funcionários. Crie uma view chamada `v_staff_performance` que exiba:

- `staff_id` e o nome completo do funcionário;
- endereço (cidade + país) onde a loja dele está localizada;
- A quantidade total de locações (`rentals`) processadas por ele;
- O valor total arrecadado através dos pagamentos que ele registrou.

*Dica*: Use LEFT JOIN para não excluir funcionários recém-contratados que ainda não processaram locações, e COALESCE para tratar nulos como zero.

```sql
drop view if exists v_staff_performance;
create view v_staff_performance as
select
    s.staff_id id,
    s.first_name || ' ' || s.last_name funcionario,
    ci.city || ', ' || co.country localizacao_loja,
    count(distinct r.rental_id) qtd_locacoes,
    coalesce(sum(p.amount), 0) total_arrecadado
from staff s
join store st on st.store_id = s.store_id
join address a on a.address_id = st.address_id
join city ci on ci.city_id = a.city_id
join country co on co.country_id = ci.country_id
left join rental r on r.staff_id = s.staff_id
left join payment p on p.rental_id = r.rental_id
group by s.staff_id, s.first_name, s.last_name, ci.city, co.country;

-- select * from v_staff_performance order by id;
```

---

## Questão 02 - View Materializada de Receita por Categoria

O relatório de receita por categoria de filme é muito pesado, pois exige cruzar `category`, `film_category`, `inventory`, `rental` e `payment`. Crie uma Materialized View chamada `mv_category_total_sales` que liste o nome da categoria e o total de receita gerado por ela. Crie um índice único na MV que permita que ela seja atualizada de forma não-bloqueante (CONCURRENTLY). Escreva o comando SQL para recarregar os dados da MV sem bloquear as consultas dos usuários do sistema.

```sql
drop materialized view if exists mv_category_total_sales;
create materialized view mv_category_total_sales as
select
    c.category_id id,
    c.name categoria,
    sum(p.amount) total_receita
from category c
join film_category fc on fc.category_id = c.category_id
join inventory i on i.film_id = fc.film_id
join rental r on r.inventory_id = i.inventory_id
join payment p on p.rental_id = r.rental_id
group by c.category_id, c.name
with data;

-- select * from mv_category_total_sales order by total_receita desc;

create unique index idx_mv_category_total_sales_id
on mv_category_total_sales(id);

refresh materialized view concurrently mv_category_total_sales;
```

---

## Questão 03 - Otimizando Filmes Atrasados

O sistema de cobrança roda a cada hora buscando locações que ainda não foram devolvidas (`return_date IS NULL`) para calcular multas. Como a tabela `rental` é grande e a maioria dos filmes já foi devolvida, um *Seq Scan* é muito caro. Crie um índice (parcial?) na tabela `rental` que indexe apenas as locações em aberto. Em seguida, escreva a consulta e use o `EXPLAIN ANALYZE` para provar que o índice está sendo utilizado.

```sql
create index idx_rental_em_aberto
on rental(rental_id)
where return_date is null;

analyze rental;

explain analyze
select rental_id, rental_date, inventory_id, customer_id
from rental
where return_date is null;
```

---

## Questão 04 - Busca Inteligente de Sinopses

Os clientes reclamam que a busca por palavras-chave na descrição dos filmes (`description`) usando `LIKE '%palavra%'` está lenta e não encontra variações da palavra (ex: "act", "acting", "actor"). Crie um índice adequado para melhorar o desempenho na busca. Em seguida, escreva uma consulta par buscar *documentary* e *drama* na descrição. Use o `EXPLAIN ANALYZE` para provar que o índice está sendo utilizado.

```sql
create index idx_film_description_fts
on film
using gin (to_tsvector('english', description));

analyze film;
set enable_seqscan = off;

explain analyze
select film_id, title, description
from film
where to_tsvector('english', description) @@ to_tsquery('english', 'documentary & drama');

set enable_seqscan = on;
```

---

## Questão 05 - Histórico do Cliente

Sempre que o cliente abre seu perfil no aplicativo, o sistema busca o histórico de pagamentos dele, ordenados do mais recente para o mais antigo:

`SELECT * FROM payment WHERE customer_id = X ORDER BY payment_date DESC`.

Para otimizar essa consulta específica, crie um índice multicoluna na tabela `payment`. Qual coluna deve vir primeiro no índice e por quê?

```sql
create index idx_payment_customer_date
on payment(customer_id, payment_date desc);

explain analyze
select *
from payment
where customer_id = 5
order by payment_date desc;
```

**Resposta:** `customer_id` vem primeiro, porque é filtrado por igualdade (`=`). Assim o Postgres vai direto ao bloco do cliente e, dentro dele, os pagamentos já estão ordenados por `payment_date`, sem precisar de um passo de `Sort`.

---

## Questão 06 - Login Case-Insensitive

O suporte técnico frequentemente busca clientes pelo e-mail, mas os atendentes não se preocupam com letras maiúsculas ou minúsculas (ex: buscam por `MARY.SMITH@...` quando o e-mail está gravado como `mary.smith@...`). Crie um **Índice Funcional** (Expression Index) na tabela `customer` que permita buscas rápidas e *case-insensitive* na coluna `email`. Crie uma consulta usando `EXPLAIN ANALYZE` para provar que o índice está sendo utilizado.

```sql
create index idx_customer_email_lower
on customer(lower(email));

analyze customer;
set enable_seqscan = off;

explain analyze
select customer_id, first_name, last_name, email
from customer
where lower(email) = lower('MARY.SMITH@sakilacustomer.org');

set enable_seqscan = on;
```

---

## Questão 07 - Validação de Datas

Ocorreu um bug no front-end que permitiu inserir locações onde a data de devolução (`return_date`) era *anterior* à data de locação (`rental_date`), gerando multas negativas. Crie um trigger `BEFORE INSERT OR UPDATE` na tabela `rental` que lance uma exceção (`RAISE EXCEPTION`) caso o `NEW.return_date` seja menor que o `NEW.rental_date`. Lembre-se de tratar o caso onde o `return_date` é `NULL` (o filme ainda está com o cliente). Realize 2 consultas teste para validar (sucesso/falha);

```sql
create or replace function fn_valida_datas_rental()
returns trigger as $$
begin
    if new.return_date is not null and new.return_date < new.rental_date then
        raise exception 'Data de devolução (%) não pode ser anterior à data de locação (%)',
            new.return_date, new.rental_date;
    end if;

    return new;
end;
$$ language plpgsql;

drop trigger if exists trg_valida_datas_rental on rental;
create trigger trg_valida_datas_rental
before insert or update on rental
for each row
execute function fn_valida_datas_rental();
```

---

## Questão 08 - Auditoria de Preços

A administração suspeita que gerentes de loja estão alterando o custo de substituição (`replacement_cost`) de filmes raros sem autorização. Crie uma tabela de auditoria chamada `film_cost_audit` (`film_id`, `old_cost`, `new_cost`, `changed_at`) e uma trigger `AFTER UPDATE` na tabela `film` que insira um registro nessa tabela **apenas** se o `replacement_cost` for efetivamente modificado (utilize a cláusula `WHEN` na criação da trigger).

```sql
drop table if exists film_cost_audit;
create table film_cost_audit (
    id serial primary key,
    film_id integer not null,
    old_cost numeric(5,2),
    new_cost numeric(5,2),
    changed_at timestamp not null default now()
);

create or replace function fn_audit_replacement_cost()
returns trigger as $$
begin
    insert into film_cost_audit (film_id, old_cost, new_cost, changed_at)
    values (old.film_id, old.replacement_cost, new.replacement_cost, now());

    return new;
end;
$$ language plpgsql;

drop trigger if exists trg_audit_replacement_cost on film;
create trigger trg_audit_replacement_cost
after update on film
for each row
when (old.replacement_cost is distinct from new.replacement_cost)
execute function fn_audit_replacement_cost();
```

---

## Questão 09 - Proteção de Catálogo

Para evitar "buracos" no catálogo e erros de chave estrangeira órfã, o banco de dados não deve permitir a exclusão de um idioma da tabela `language` caso existam filmes cadastrados que o utilizem (seja como idioma original ou de áudio). Crie uma trigger `BEFORE DELETE` na tabela `language` que verifique as tabelas `film` (`language_id` e `original_language_id`). Se houver filmes vinculados, a exclusão deve ser abortada com uma mensagem de erro amigável.

```sql
create or replace function fn_protege_language()
returns trigger as $$
declare
    qtd_filmes integer;
begin
    select count(*)
    into qtd_filmes
    from film
    where language_id = old.language_id
       or original_language_id = old.language_id;

    if qtd_filmes > 0 then
        raise exception 'Não é possível excluir o idioma "%": existem % filme(s) vinculado(s) a ele.',
            trim(old.name), qtd_filmes;
    end if;

    return old;
end;
$$ language plpgsql;

drop trigger if exists trg_protege_language on language;
create trigger trg_protege_language
before delete on language
for each row
execute function fn_protege_language();
```

---

## Questão 10 - Sincronização de Estatísticas

Para evitar contar as linhas da tabela `rental` toda vez que quisermos saber quantos filmes um cliente já alugou, vamos manter uma tabela de estatísticas.

- Crie a tabela `customer_rental_stats` (`customer_id` PK, `total_rentals` INT DEFAULT 0).
- Popule-a inicialmente com os dados atuais.
- Crie uma trigger `AFTER INSERT` na tabela `rental` que, a cada nova locação, atualize (incremento `+1`) o contador do respectivo cliente na tabela de estatísticas (verifique a existência).

```sql
drop table if exists customer_rental_stats;
create table customer_rental_stats (
    customer_id integer primary key,
    total_rentals integer default 0
);

insert into customer_rental_stats (customer_id, total_rentals)
select
    c.customer_id,
    count(r.rental_id)
from customer c
left join rental r on r.customer_id = c.customer_id
group by c.customer_id;


create or replace function fn_atualiza_rental_stats()
returns trigger as $$
begin
    if exists (select 1 from customer_rental_stats where customer_id = new.customer_id) then
        update customer_rental_stats
        set total_rentals = total_rentals + 1
        where customer_id = new.customer_id;
    else
        insert into customer_rental_stats (customer_id, total_rentals)
        values (new.customer_id, 1);
    end if;

    return new;
end;
$$ language plpgsql;

drop trigger if exists trg_atualiza_rental_stats on rental;
create trigger trg_atualiza_rental_stats
after insert on rental
for each row
execute function fn_atualiza_rental_stats();
```