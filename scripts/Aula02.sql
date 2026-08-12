drop table if exists funcionario cascade;



create table funcionario(
    cpf char(11) primary key,
    pnome varchar(50) not null,
    unome varchar(50) not null,
    email varchar(50) not null unique,
    endereco varchar(100),
    salario numeric(7,2),
    data_nasc date,
    sexo char(1),
    cpf_supervisor char(11),
    numero_departamento smallint,

    constraint funcionario_salario_check
    check (salario >= 2000 and salario <= 15000)
);

create table departamentoo(
    numero smallint primary key,
    nome varchar(50) unique,
    cpf_gerente char(11)
);