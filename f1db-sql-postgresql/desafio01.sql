--Questao 01
drop materialized view if exists mv_driver_season_summary;
create materialized view mv_driver_season_summary as
select
    r.year ano,
    d.id piloto_id,
    d.name piloto,
    count(*) total_corridas,
    count(case when rd.position_number = 1 then 1 end) vitorias,
    count(case when rd.position_number <= 3 then 1 end) podios,
    count(case when rd.race_reason_retired is not null then 1 end) abandonos,
    coalesce(sum(rd.race_points), 0) total_pontos
from race_data rd
join race r on r.id = rd.race_id
join driver d on d.id = rd.driver_id
where rd.type = 'RACE_RESULT'
group by r.year, d.id, d.name
with data;


create unique index idx_mv_driver_season_summary
on mv_driver_season_summary(ano, piloto_id);


refresh materialized view concurrently mv_driver_season_summary;


select *
from mv_driver_season_summary
where piloto = 'Ayrton Senna'
order by ano desc
limit 10;

--Questao02

drop table if exists points_adjustment_audit;
create table points_adjustment_audit (
    id         serial primary key,
    year       int not null,
    driver_id  varchar(100) not null,
    old_points decimal(8,2),
    new_points decimal(8,2),
    changed_at timestamptz default now()
);


create or replace function fn_audit_points_adjustment()
returns trigger as $$
begin
    insert into points_adjustment_audit (year, driver_id, old_points, new_points)
    values (old.year, old.driver_id, old.points, new.points);

    return new;
end;
$$ language plpgsql;


drop trigger if exists trg_audit_points_adjustment on season_driver_standing;
create trigger trg_audit_points_adjustment
after update on season_driver_standing
for each row
when (old.points is distinct from new.points)
execute function fn_audit_points_adjustment();


update season_driver_standing
set points = points + 100
where year = 1993
  and driver_id = (select id from driver where name = 'Ayrton Senna');


select * from points_adjustment_audit;


--Questao03

create or replace function fn_protege_driver()
returns trigger as $$
declare
    qtd_registros integer;
begin
    select count(*)
    into qtd_registros
    from race_data
    where driver_id = old.id;

    if qtd_registros > 0 then
        raise exception 'Não é possível excluir pilotos sem registros',
            old.name, qtd_registros;
    end if;

    return old;
end;
$$ language plpgsql;

drop trigger if exists trg_protege_driver on driver;
create trigger trg_protege_driver
before delete on driver
for each row
execute function fn_protege_driver();

delete from driver where name = 'Ayrton Senna';

select d.id, d.name
from driver d
where not exists (
    select 1
    from race_data rd
    where rd.driver_id = d.id
)
limit 5;

