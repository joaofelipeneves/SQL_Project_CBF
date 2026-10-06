drop table championships cascade constraints;

drop table seasons cascade constraints;

drop table rounds cascade constraints;

drop table teams cascade constraints;

drop table contracts cascade constraints;

drop table people cascade constraints;

drop table players cascade constraints;

drop table referees cascade constraints;

drop table stadiums cascade constraints;

drop table matches cascade constraints;

drop table tickets cascade constraints;

drop table buys cascade constraints;

drop table participates_in cascade constraints;

drop table loaned_to cascade constraints;

create table championships(c_name varchar(50) primary key);

-- Seasons can have no participating teams this way
-- We can remove the foreign key constraint from 'participates_in' and add a trigger to ensure that a season has 20 teams participating
create table seasons(
	c_name varchar(50),
	s_year int,
	prize number not null,
	primary key(c_name, s_year),
	constraint fk_seasons foreign key(c_name) references championships(c_name),
	check(prize > 0),
	check(s_year > 0)
);

create table rounds(
	c_name varchar(50),
	s_year int,
	r_number int,
	constraint pk_rounds primary key(c_name, s_year, r_number),
	constraint fk_rounds foreign key(c_name, s_year) references seasons(c_name, s_year),
	check(r_number > 0)
);

create table teams(
	nipc varchar(10) primary key,
	t_name varchar(50) not null unique
);

create table participates_in(
	c_name varchar(50),
	s_year int,
	nipc varchar(10),
	constraint pk_participates_in primary key(c_name, s_year, nipc)
);

create table people(
	nif varchar(10) primary key,
	p_name varchar(50) not null,
	birthday date not null,
	nationality varchar(50) not null
);

create table contracts(
	id varchar(50) primary key,
	nipc varchar(10) not null,
	nif varchar(10) not null,
	starts date not null,
	ends date not null,
	salary number not null,
	constraint fk_c_nipc foreign key(nipc) references teams(nipc),
	constraint fk_c_nif foreign key(nif) references people(nif),
	check(starts < ends), 
	check(salary > 0)
);

create table players(
	nif varchar(10) primary key,
	position varchar(50) not null,
	constraint fk_p_nif foreign key(nif) references people(nif)
);

create table referees(
	nif varchar(10) primary key,
	license varchar(10) not null unique,
	constraint fk_r_nif foreign key(nif) references people(nif)
);

create table stadiums(
	s_name varchar(50) primary key,
	capacity int not null,
	city varchar(50) not null,
	street varchar(50) not null,
	constraint u_stadium unique (city, street),
	check(capacity > 0)
);

create table matches(
	s_name varchar(50),
	date_ date,
	home_team_nipc varchar(10) not null,
	away_team_nipc varchar(10) not null,
	home_team_goals int not null,
	away_team_goals int not null,
	c_name varchar(50) not null,
	s_year int not null,
	r_number int not null,
	nif varchar(10) not null,
	constraint pk_matches primary key(s_name, date_),
	constraint fk_s_name foreign key(s_name) references stadiums(s_name),
	constraint fk_home_team_nipc foreign key(home_team_nipc) references teams(nipc),
	constraint fk_away_team_nipc foreign key(away_team_nipc) references teams(nipc),
	constraint fk_round foreign key(c_name, s_year, r_number) references rounds(c_name, s_year, r_number),
	constraint fk_referee foreign key(nif) references referees(nif),
	constraint u_home_away_team_match unique (c_name, s_year, home_team_nipc, away_team_nipc),
	check(home_team_goals >= 0),
	check(away_team_goals >= 0)
);

create table tickets(
	s_name varchar(50),
	date_ date,
	n int,
	price int not null,
	constraint pk_tickets primary key(s_name, date_, n),
	constraint fk_t_match foreign key(s_name, date_) references matches(s_name, date_),
	check(price >= 0),
	check(n > 0)
);

create table buys(
	s_name varchar(50),
	date_ date,
	n int,
	nif varchar(10) not null,
	constraint pk_buys primary key(s_name, date_, n),
	constraint fk_b_ticket foreign key(s_name, date_, n) references tickets(s_name, date_, n),
	constraint fk_b_nif foreign key(nif) references people(nif),
	check(n > 0)
);

create table loaned_to(
	id varchar(50) primary key,
	nipc varchar(10) not null,
	starts date not null,
	ends date not null,
	price number not null,
	constraint fk_lt_contract foreign key(id) references contracts(id),
	constraint fk_lt_nipc foreign key(nipc) references teams(nipc),
	check(starts < ends), -- maybe minimum loan duration
	check(price >= 0)
);

create or replace trigger no_overlapping_contracts 
before insert or update on contracts 
for each row 
declare overlapping_count number;
begin
	select
		count(*) into overlapping_count
	from
		contracts
	where
		nif = :new.nif
		and starts < :new.ends
		and ends > :new.starts;
	if overlapping_count > 0 then raise_application_error(-20000, 'Overlapping contracts');
end if;
end;
/ 

-- Check if the teams are from the same championship and season
create or replace trigger check_teams_championship 
before insert or update on matches 
for each row 
declare team_count int;
begin
	select count(*) into team_count from participates_in
	where
		c_name = :new.c_name
		and s_year = :new.s_year
		and nipc in (:new.home_team_nipc, :new.away_team_nipc);
	if team_count != 2 then 
		raise_application_error(-20001, 'Teams ' || :new.home_team_nipc || ' and ' || :new.away_team_nipc || ' are not in the same championship and season');
	end if;
end;
/

-- Check if NIF starts with N prefix
create or replace trigger check_nif_prefix
before insert or update on people
for each row
begin
	if substr(:new.nif, 1, 1) != 'N' then
		raise_application_error(-20002, 'NIF must start with N');
	end if;
end;
/

-- Check if NIPC starts with T prefix
create or replace trigger check_nipc_prefix
before insert or update on teams
for each row
begin
	if substr(:new.nipc, 1, 1) != 'T' then
		raise_application_error(-20003, 'NIPC must start with T');
	end if;
end;
/

-- Check if referee has more than one game on the day
create or replace trigger check_games_referee
after insert or update on matches
declare
    games_count int;
begin
    select count(*) into games_count from (
			select nif, date_, count(*) as count
			from matches
			group by nif, date_
			having count(*) > 1
		);
    if games_count > 1 then
        raise_application_error(-20004, 'Referee has more than one game on the day');
    end if;
end;
/

-- Set ticket number automatically
create or replace trigger set_ticket_number
before insert on tickets
for each row
begin
	select count(*) + 1 into :new.n from tickets where s_name = :new.s_name and date_ = :new.date_;
end;
/

-- Ensure team is not playing against itself
create or replace trigger check_same_team
before insert or update on matches
for each row
begin
	if :new.home_team_nipc = :new.away_team_nipc then
		raise_application_error(-20006, 'Team cannot play against itself');
	end if;
end;
/

-- Ensure stadium is not being used more than once in the same round
create or replace trigger check_games_stadium 
after insert or update on matches
declare
  stadium_count int;
begin
  select count(*) into stadium_count from (select s_name, date_ from matches group by s_name, date_ having count(*) > 1);
  
  if stadium_count > 0 then
    raise_application_error(-20004, 'This stadium already has a match in this round');
  end if;
  end;
/

-- Ensure match date year is same as season year
create or replace trigger check_same_year
before insert or update on matches
for each row
declare
  match_year number;
begin
  match_year := extract(year from :new.date_);

  if :new.s_year != match_year then 
    raise_application_error(-20001, 'Different match year and season');
  end if;
end;
/

-- Functions

-- Get NIPC by name (helper function)
create or replace function get_nipc(t_name varchar) return varchar as
	nipc varchar(10);
begin
	select nipc into nipc from teams where t_name = get_nipc.t_name;
	return nipc;
end;
/

-- Procedures 

-- Issue match tickets
create or replace procedure issue_tickets(s_name varchar, date_ date, amount int, price int) as
begin
	for i in 1..amount loop
		insert into tickets (s_name, date_, price) values (s_name, date_, price);
	end loop;
end;
/

create or replace type team_nipcs as table of varchar(10);
/

-- Create rounds
create or replace procedure create_rounds(c_name varchar, s_year int, rounds int) as
begin
	for i in 1..rounds loop
		insert into rounds values (c_name, s_year, i);
	end loop;
end;
/

-- Create season
create or replace procedure create_season(c_name varchar, s_year int, prize number, teams team_nipcs) as
begin
	insert into seasons values (c_name, s_year, prize);

	for i in 1..teams.count loop
		insert into participates_in values (c_name, s_year, teams(i));
	end loop;

	for i in 1..(2 * (teams.count - 1)) loop
		insert into rounds values (c_name, s_year, i);
	end loop;
end;
/

-- Views


-- Missing season matchups
create or replace view season_missing_matchups as
select c_name, s_year, home_team_nipc, away_team_nipc from (
    select t1.c_name, t1.s_year, t1.nipc as home_team_nipc, t2.nipc as away_team_nipc from participates_in t1, participates_in t2
    where t1.nipc != t2.nipc and t1.c_name = t2.c_name and t1.s_year = t2.s_year    
    minus
    select c_name, s_year, home_team_nipc, away_team_nipc from matches
);

-- Get teams that did not play in a round
create or replace view season_rounds_missing_teams as 
select c_name, s_year, r_number, nipc from (
    select c_name, s_year, r_number, nipc from rounds natural inner join participates_in
    minus
    (select c_name, s_year, r_number, home_team_nipc as nipc from matches
    union
    select c_name, s_year, r_number, away_team_nipc as nipc from matches)
);
 

-- Current team players view
create or replace view current_team_players as
select nipc, p_name, t_name, position, salary from contracts
natural join players
natural join teams
natural join people
where sysdate between starts and ends;

-- Home stats view
create or replace view home_stats as
select 
	c_name,
	s_year,
	t_name,
	nipc,
	goals_scored,
	goals_suffered,
	goal_difference,
	wins,
	draws,
	losses,
	games,
	3 * wins + draws as pts
 from (
	select
		c_name,
		s_year,
		t_name,
		nipc,
		sum(home_team_goals) as goals_scored,
		sum(away_team_goals) as goals_suffered,
		sum(home_team_goals - away_team_goals) as goal_difference,
		sum(case when home_team_goals > away_team_goals then 1 else 0 end) as wins,
		sum(case when home_team_goals = away_team_goals then 1 else 0 end) as draws,
		sum(case when home_team_goals < away_team_goals then 1 else 0 end) as losses,
		count(*) as games
	from
		matches
		join teams on home_team_nipc = nipc
	group by c_name, s_year, t_name, nipc
)
order by c_name desc, s_year desc, pts desc, wins desc, goals_scored desc, goal_difference asc;

-- Away stats view
create
or replace view away_stats as
select c_name,
		s_year,
		t_name,
		nipc,
		goals_scored,
		goals_suffered,
		goal_difference,
		wins,
		draws,
		losses,
		games,
		3 * wins + draws as pts 
	from (
		select
			c_name,
			s_year,
			t_name,
			nipc,
			sum(away_team_goals) as goals_scored,
			sum(home_team_goals) as goals_suffered,
			sum(away_team_goals - home_team_goals) as goal_difference,
			sum(case when away_team_goals > home_team_goals then 1 else 0 end) as wins,
			sum(case when away_team_goals = home_team_goals then 1 else 0 end) as draws,
			sum(case when away_team_goals < home_team_goals then 1 else 0 end) as losses,
			count(*) as games
		from
			matches
			join teams on away_team_nipc = nipc
		group by c_name, s_year, t_name, nipc
    )
order by c_name desc, s_year desc, pts desc, wins desc, goals_scored desc, goal_difference asc;


-- Championship season table view
create or replace view championship_season as
select 
    c_name,
	s_year,
	t_name,
	nipc,
    row_number() over (partition by c_name, s_year order by pts desc, wins desc, goals_scored desc, goal_difference asc) as position,
    goals_scored,
    goals_suffered,
    goal_difference,
    wins,
    draws,
    losses,
    games,
    pts
    from (
    select
        c_name,
        s_year,
        t_name,
        nipc,
        sum(goals_scored) as goals_scored,
        sum(goals_suffered) as goals_suffered,
        sum(goal_difference) as goal_difference,
        sum(wins) as wins,
        sum(draws) as draws,
        sum(losses) as losses,
        sum(games) as games,
        sum(pts) as pts
    from 
        (select * from home_stats
        union all
        select * from away_stats)
    group by c_name, s_year, t_name, nipc);

-- Available tickets view
create or replace view available_tickets as
select s_name, date_, count(*) as available
from ((select s_name, date_, n from tickets) minus (select s_name, date_, n from buys))
group by s_name, date_;

-- Seasons winners view
create or replace view season_winners as
select c_name, s_year, t_name, nipc, pts
from championship_season
where position = 1;

	
-- Data
-- Data
insert all 
	into championships values ('Brasileirao A') 
	into championships values	('Brasileirao B') 
	into championships values	('Brasileirao C')
select * from dual;

insert all 
--times serie A
	into teams values ('T123456789', 'Flamengo')
	into teams values ('T123456888', 'Internacional')
	into teams values ('T321654987', 'Santos')
    into teams values ('T987654321', 'Corinthians')
	into teams values ('T123789456', 'Sao Paulo')
	into teams values ('T987321654', 'Palmeiras')
    into teams values ('T456123789', 'Vasco')
	into teams values ('T654987321', 'Botafogo')
	into teams values ('T789456123', 'Fluminense')
    into teams values ('T456789123', 'Gremio')
	into teams values ('T654321987', 'Bragantino')
	into teams values ('T789123456', 'Atletico Mineiro')
    
    into teams values ('T123456666', 'Cuiaba')
    into teams values ('T123456777', 'Atletico Goianiense')
	into teams values ('T123456444', 'Chapecoense')
	into teams values ('T123456333', 'Operario')
	into teams values ('T123456222', 'Vila Nova')
	into teams values ('T123456111', 'Novorizontino')
	into teams values ('T123456000', 'CRB')
	into teams values ('T123111111', 'Mirassol')
	into teams values ('T123111222', 'Brusque')
	into teams values ('T123111333', 'Botafogo SP')
	into teams values ('T123111444', 'Avai')
	into teams values ('T123111448', 'Amazonas')
	into teams values ('T123111555', 'Ituano')
    into teams values ('T123456555', 'America Mineiro')
    
	into teams values ('T321987654', 'Cruzeiro')
	into teams values ('T456789321', 'Atletico Paranaense')
	into teams values ('T654321789', 'Coritiba')
	into teams values ('T789123654', 'Bahia')
	into teams values ('T321987456', 'Vitoria')
	into teams values ('T456321789', 'Sport')
	into teams values ('T654789123', 'Santa Cruz')

	into teams values ('T321789654', 'Ceara')
	into teams values ('T456987328', 'Fortaleza')
	into teams values ('T654123789', 'Goias')
	into teams values ('T789321654', 'Goiania')
	into teams values ('T321789452', 'Ponte Preta')
	into teams values ('T456987326', 'Guarani')

	into teams values ('T321789454', 'Londrina')
    
    into teams values ('T654123782', 'Sao Caetano')
	into teams values ('T789321656', 'Santo Andre')
	into teams values ('T321789453', 'Juventude')
    into teams values ('T789321456', 'Nautico')    
    into teams values ('T456987322', 'Criciuma')
	into teams values ('T654123783', 'Joinville')
	into teams values ('T789321653', 'Parana')
	into teams values ('T456987321', 'Paysandu')
	into teams values ('T654123781', 'Remo')
	into teams values ('T789321651', 'Tuna Luso')
	into teams values ('T321789456', 'Sao Raimundo')
	into teams values ('T654123788', 'Nacional')
select * from dual;
    
        call create_season(
	'Brasileirao A', 
	2022, 
	1100000, 
	team_nipcs(
		get_nipc('Londrina'),
		get_nipc('Goias'),
		get_nipc('Santos'),
		get_nipc('Fluminense'),
		get_nipc('Sao Paulo'),
		get_nipc('Palmeiras'),
		get_nipc('Vitoria'),
		get_nipc('Botafogo'),
		get_nipc('Bragantino'),
		get_nipc('Atletico Mineiro')
		)
	);
    
        call create_season(
	'Brasileirao A', 
	2023, 
	1200000, 
	team_nipcs(
		get_nipc('Flamengo'),
		get_nipc('Internacional'),
		get_nipc('Santos'),
		get_nipc('Fluminense'),
		get_nipc('Sao Paulo'),
		get_nipc('Palmeiras'),
		get_nipc('Bahia'),
		get_nipc('Botafogo'),
		get_nipc('Bragantino'),
		get_nipc('Atletico Mineiro')
		)
	);
    
    call create_season(
	'Brasileirao A', 
	2024, 
	1300000, 
	team_nipcs(
		get_nipc('Flamengo'),
		get_nipc('Internacional'),
		get_nipc('Santos'),
		get_nipc('Corinthians'),
		get_nipc('Sao Paulo'),
		get_nipc('Palmeiras'),
		get_nipc('Vasco'),
		get_nipc('Botafogo'),
		get_nipc('Gremio'),
		get_nipc('Atletico Mineiro')
		)
	); 
    
    call create_season(
	'Brasileirao B', 
	2022, 
	500000, 
	team_nipcs(
		get_nipc('Operario'),
		get_nipc('Vila Nova'),
		get_nipc('Novorizontino'),
		get_nipc('CRB'),
		get_nipc('Mirassol'),
		get_nipc('Brusque'),
		get_nipc('Amazonas'),
		get_nipc('Ituano'),
		get_nipc('Londrina'),
		get_nipc('Coritiba')
		)
	);
    
        call create_season(
	'Brasileirao B', 
	2023, 
	510000, 
	team_nipcs(
		get_nipc('Operario'),
		get_nipc('Vila Nova'),
		get_nipc('America Mineiro'),
		get_nipc('CRB'),
		get_nipc('Mirassol'),
		get_nipc('Brusque'),
		get_nipc('Amazonas'),
		get_nipc('Ituano'),
		get_nipc('Londrina'),
		get_nipc('Coritiba')
		)
	);
    
call create_season(
	'Brasileirao B', 
	2024, 
	520000, 
	team_nipcs(
		get_nipc('Operario'),
		get_nipc('Cuiaba'),
		get_nipc('America Mineiro'),
		get_nipc('CRB'),
		get_nipc('Mirassol'),
		get_nipc('Brusque'),
		get_nipc('Amazonas'),
		get_nipc('Ituano'),
		get_nipc('Londrina'),
		get_nipc('Coritiba')
		)
	);
    
    
call create_season(
	'Brasileirao C', 
	2022, 
	250000, 
	team_nipcs(
		get_nipc('Tuna Luso'),
		get_nipc('Nacional'),
		get_nipc('Paysandu'),
		get_nipc('Remo'),
		get_nipc('Sao Caetano'),
		get_nipc('Santo Andre'),
		get_nipc('Joinville'),
		get_nipc('Parana'),
		get_nipc('Criciuma'),
		get_nipc('Nautico')
		)
	);
    
    call create_season(
	'Brasileirao C', 
	2023, 
	260000, 
	team_nipcs(
		get_nipc('Tuna Luso'),
		get_nipc('Nacional'),
		get_nipc('Paysandu'),
		get_nipc('Remo'),
		get_nipc('Sao Caetano'),
		get_nipc('Santo Andre'),
		get_nipc('Joinville'),
		get_nipc('Parana'),
		get_nipc('Criciuma'),
		get_nipc('Guarani')
		)
	);

call create_season(
	'Brasileirao C', 
	2024, 
	270000, 
	team_nipcs(
		get_nipc('Tuna Luso'),
		get_nipc('Nacional'),
		get_nipc('Paysandu'),
		get_nipc('Remo'),
		get_nipc('Sao Caetano'),
		get_nipc('Santo Andre'),
		get_nipc('Joinville'),
		get_nipc('Parana'),
		get_nipc('Criciuma'),
		get_nipc('Avai')
		)
	);
 
 insert all
--jogadores 
    into people values ('N112233445', 'Marcos Rocha', date '1988-12-11', 'Brazil')
    into people values ('N223344556', 'Everton Ribeiro', date '1989-04-10', 'Brazil')
    into people values ('N334455667', 'Gabriel Barbosa', date '1996-08-30', 'Brazil')
    into people values ('N445566778', 'Giorgian De Arrascaeta', date '1994-06-01', 'Uruguay')
    into people values ('N556677889', 'Bruno Henrique', date '1990-12-30', 'Brazil')
    into people values ('N667788990', 'Pedro Guilherme', date '1997-06-20', 'Brazil')
    into people values ('N778899001', 'Thiago Silva', date '1984-09-22', 'Brazil')
    into people values ('N889900112', 'Miranda', date '1984-09-07', 'Brazil')
    into people values ('N990011223', 'Renan Lodi', date '1998-04-08', 'Brazil')
    into people values ('N001122334', 'Gerson', date '1997-05-20', 'Brazil')
    
    into people values ('N001223344', 'Lucas Paquetá', date '1997-08-27', 'Brazil')
    into people values ('N002334455', 'Vinícius Júnior', date '2000-07-12', 'Brazil')
    into people values ('N003445566', 'Neymar Jr.', date '1992-02-05', 'Brazil')
    into people values ('N004556677', 'Casemiro', date '1992-02-23', 'Brazil')
    into people values ('N005667788', 'Alisson Becker', date '1992-10-02', 'Brazil')
    into people values ('N006778899', 'Philippe Coutinho', date '1992-06-12', 'Brazil')
    into people values ('N007889900', 'Fabinho', date '1993-10-23', 'Brazil')
    into people values ('N008990011', 'Éder Militão', date '1998-01-18', 'Brazil')
    into people values ('N009001122', 'Fred', date '1993-03-05', 'Brazil')
    into people values ('N010112233', 'Gabriel Jesus', date '1997-04-03', 'Brazil')
    
     into people values ('N010223344', 'Rafinha', DATE '1995-08-09', 'Brazil')
    into people values ('N011334455', 'Lucas Moura', DATE '1992-08-13', 'Brazil')
    into people values ('N012445566', 'David Luiz', DATE '1987-04-22', 'Brazil')
 into people values ('N013556677', 'Filipe Luís', DATE '1985-08-09', 'Brazil')
 into people values ('N014667788', 'Dani Alves', DATE '1983-05-06', 'Brazil')
 into people values ('N015778899', 'Marcelo Vieira', DATE '1988-05-12', 'Brazil')
 into people values ('N016889900', 'Willian Borges', DATE '1988-08-09', 'Brazil')
 into people values ('N017990011', 'Fernandinho', DATE '1985-05-04', 'Brazil')
 into people values ('N018001122', 'Allan Marques', DATE '1991-01-08', 'Brazil')
 into people values ('N019112233', 'Douglas Costa', DATE '1990-09-14', 'Brazil')
 
 into people values ('N030223344', 'Marquinhos', DATE '1994-05-14', 'Brazil')
into people values ('N031334455', 'Eduardo Camavinga', DATE '2002-11-10', 'France')
into people values ('N032445566', 'Erling Haaland', DATE '2000-07-21', 'Norway')
into people values ('N033556677', 'Jadon Sancho', DATE '2000-03-25', 'England')
into people values ('N034667788', 'Pedri', DATE '2002-11-25', 'Spain')
into people values ('N035778899', 'Jude Bellingham', DATE '2003-06-29', 'England')
into people values ('N036889900', 'Ansu Fati', DATE '2002-10-31', 'Spain')
into people values ('N037990011', 'Giovanni Reyna', DATE '2002-11-13', 'USA')
into people values ('N038001122', 'Mason Mount', DATE '1999-01-10', 'England')
into people values ('N039112233', 'Federico Valverde', DATE '1998-07-22', 'Uruguay')

into people values ('N040223344', 'João Félix', DATE '1999-11-10', 'Portugal')
into people values ('N041334455', 'Kai Havertz', DATE '1999-06-11', 'Germany')
into people values ('N042445566', 'Alphonso Davies', DATE '2000-11-02', 'Canada')
into people values ('N043556677', 'Christian Pulisic', DATE '1998-09-18', 'USA')
into people values ('N044667788', 'Rúben Dias', DATE '1997-05-14', 'Portugal')
into people values ('N045778899', 'Matthijs de Ligt', DATE '1999-08-12', 'Netherlands')
into people values ('N046889900', 'Ferran Torres', DATE '2000-02-29', 'Spain')
into people values ('N047990011', 'Marcus Rashford', DATE '1997-10-31', 'England')
into people values ('N048001122', 'Declan Rice', DATE '1999-01-14', 'England')
into people values ('N049112233', 'Sergiño Dest', DATE '2000-11-03', 'USA')

 into people values ('N020223344', 'Alex Sandro', DATE '1991-01-26', 'Brazil')
 into people values ('N021334455', 'Rodrigo Caio', DATE '1993-08-17', 'Brazil')
 into people values ('N022445566', 'Arthur Melo', DATE '1996-08-12', 'Brazil')
 into people values ('N023556677', 'Richarlison', DATE '1997-05-10', 'Brazil')
 into people values ('N024667788', 'Lucas Veríssimo', DATE '1995-07-02', 'Brazil')
 into people values ('N025778899', 'Bruno Guimarães', DATE '1997-11-16', 'Brazil')
 into people values ('N026889900', 'Matheus Cunha', DATE '1999-05-27', 'Brazil')
 into people values ('N027990011', 'Gabriel Magalhães', DATE '1997-12-19', 'Brazil')
 into people values ('N028001122', 'Emerson Royal', DATE '1999-01-14', 'Brazil')
 into people values ('N029112233', 'Antony Matheus', DATE '2000-02-24', 'Brazil')
 
 into people values ('N050223344', 'André Almeida', date '1999-07-10', 'Brazil')
into people values ('N051334455', 'Carlos Eduardo', date '1998-11-14', 'Brazil')
into people values ('N052445566', 'Diego Souza', date '1997-09-15', 'Brazil')
into people values ('N053556677', 'Evandro Silva', date '1996-04-22', 'Brazil')
into people values ('N054667788', 'Fernando Santos', date '1995-02-17', 'Brazil')
into people values ('N055778899', 'Gustavo Henrique', date '1994-01-13', 'Brazil')
into people values ('N056889900', 'Henrique Dourado', date '1993-08-18', 'Brazil')
into people values ('N057990011', 'Isaac Lima', date '1992-05-12', 'Brazil')
into people values ('N058001122', 'João Victor', date '1991-03-25', 'Brazil')
into people values ('N059112233', 'Lucas Silva', date '1990-06-30', 'Brazil')

into people values ('N060223344', 'Marcos Vinícius', date '1989-07-22', 'Brazil')
into people values ('N061334455', 'Nathan Ribeiro', date '1988-08-14', 'Brazil')
into people values ('N062445566', 'Otávio Júnior', date '1987-09-23', 'Brazil')
into people values ('N063556677', 'Paulo Ricardo', date '1986-04-16', 'Brazil')
into people values ('N064667788', 'Quirino Souza', date '1985-05-27', 'Brazil')
into people values ('N065778899', 'Ricardo Goulart', date '1984-06-14', 'Brazil')
into people values ('N066889900', 'Samuel Xavier', date '1983-11-30', 'Brazil')
into people values ('N067990011', 'Thiago Maia', date '1998-03-10', 'Brazil')
into people values ('N068001122', 'Ueliton Alves', date '1997-12-20', 'Brazil')
into people values ('N069112233', 'Vinícius Araújo', date '1996-01-05', 'Brazil')

into people values ('N070223344', 'Wellington Silva', date '1995-02-22', 'Brazil')
into people values ('N071334455', 'Xavier Carvalho', date '1994-04-18', 'Brazil')
into people values ('N072445566', 'Yago Felipe', date '1993-07-03', 'Brazil')
into people values ('N073556677', 'Zeca Almeida', date '1992-10-29', 'Brazil')
into people values ('N074667788', 'Adriano Correia', date '1991-01-12', 'Brazil')
into people values ('N075778899', 'Bruno César', date '1990-03-17', 'Brazil')
into people values ('N076889900', 'Cláudio Winck', date '1989-05-01', 'Brazil')
into people values ('N077990011', 'Deyverson Silva', date '1988-06-28', 'Brazil')
into people values ('N078001122', 'Elias Mendes', date '1987-09-10', 'Brazil')
into people values ('N079112233', 'Fabio Santos', date '1986-12-14', 'Brazil')
into people values ('N080223344', 'Gustavo Scarpa', date '1985-02-18', 'Brazil')
into people values ('N081334455', 'Hernanes Oliveira', date '1984-04-23', 'Brazil')
into people values ('N082445566', 'Igor Vinícius', date '1983-07-30', 'Brazil')
into people values ('N083556677', 'Jean Mota', date '1982-10-15', 'Brazil')
into people values ('N084667788', 'Kaio Jorge', date '1981-01-09', 'Brazil')
into people values ('N085778899', 'Lucas Veríssimo', date '1980-03-24', 'Brazil')


--Arbitros
	into people values ('N123456789', 'Jorge Jesus', date '1954-07-24', 'Portugal')
	into people values ('N987654321', 'Tite', date '1961-05-25', 'Brazil')
	into people values ('N123789456', 'Hernan Crespo', date '1975-07-05', 'Argentina')
	into people values ('N987321654', 'Abel Ferreira', date '1978-08-01', 'Portugal')
	into people values ('N456123789', 'Marcelo Cabo', date '1976-06-15', 'Brazil')
	into people values ('N654987321', 'Marcelo Chamusca', date '1966-04-15', 'Brazil')
	into people values ('N789456123', 'Roger Machado', date '1975-04-25', 'Brazil')
	into people values ('N321654987', 'Fernando Diniz', date '1974-11-27', 'Brazil')
	into people values ('N456789123', 'Felipao', date '1948-09-20', 'Brazil')
	into people values ('N654321987', 'Mauricio Barbieri', date '1981-06-27', 'Brazil')
select * from dual;

insert all 
	into referees values ('N123456789', 'L111115678')
	into referees values ('N987654321', 'L111119876')
	into referees values ('N123789456', 'L111115432')
	into referees values ('N987321654', 'L111112109')
	into referees values ('N456123789', 'L111118765')
	into referees values ('N654987321', 'L111114321')
	into referees values ('N789456123', 'L111116789')
	into referees values ('N321654987', 'L111113456')
	into referees values ('N456789123', 'L111110987')
	into referees values ('N654321987', 'L111116543')
    
    
    into players values('N112233445', 'Lateral Direiro')
    into players values('N223344556', 'Meio Campo')
    into players values('N334455667', 'Atacante')
    into players values('N445566778', 'Meio Campo')
    into players values('N556677889', 'Ponta Esquerda')
    into players values('N667788990', 'Atacante')
    into players values('N778899001', 'Defensor')
    into players values('N889900112', 'Meio Campo')
    into players values('N990011223', 'Lateral Direito')
    into players values('N001122334', 'Lateral Esquerdo') 
    
    into players values ('N001223344', 'Meio Campo')
    into players values ('N002334455', 'Atacante')
    into players values ('N003445566', 'Atacante')
    into players values ('N004556677', 'Volante')
    into players values ('N005667788', 'Goleiro')
    into players values ('N006778899', 'Meio Campo')
    into players values ('N007889900', 'Volante')
    into players values ('N008990011', 'Defensor')
    into players values ('N009001122', 'Meio Campo')
    into players values ('N010112233', 'Atacante')
    
    into players values ('N030223344', 'Defensor')
    into players values ('N031334455', 'Meio-campista')
    into players values ('N032445566', 'Atacante')
    into players values ('N033556677', 'Atacante')
    into players values ('N034667788', 'Meio-campista')
    into players values ('N035778899', 'Meio-campista')
    into players values ('N036889900', 'Atacante')
    into players values ('N037990011', 'Meio-campista')
    into players values ('N038001122', 'Meio-campista')
    into players values ('N039112233', 'Meio-campista')

    into players values ('N040223344', 'Atacante')
    into players values ('N041334455', 'Meio-campista')
    into players values ('N042445566', 'Defensor')
    into players values ('N043556677', 'Atacante')
    into players values ('N044667788', 'Defensor')
    into players values ('N045778899', 'Defensor')
    into players values ('N046889900', 'Atacante')
    into players values ('N047990011', 'Atacante')
    into players values ('N048001122', 'Meio-campista')
    into players values ('N049112233', 'Defensor')
    
    into players values ('N010223344', 'Lateral Direito')
    into players values ('N011334455', 'Meio Campo')
    into players values ('N012445566', 'Defensor')
    into players values ('N013556677', 'Lateral Esquerdo')
    into players values ('N014667788', 'Lateral Direito')
    into players values ('N015778899', 'Lateral Esquerdo')
    into players values ('N016889900', 'Ponta Direita')
    into players values ('N017990011', 'Volante')
    into players values ('N018001122', 'Meio Campo')
    into players values ('N019112233', 'Ponta Direita')
    into players values ('N020223344', 'Lateral Esquerdo')
    into players values ('N021334455', 'Defensor')
    into players values ('N022445566', 'Meio Campo')
    into players values ('N023556677', 'Atacante')
    into players values ('N024667788', 'Defensor')
    into players values ('N025778899', 'Meio Campo')
    into players values ('N026889900', 'Atacante')
    into players values ('N027990011', 'Defensor')
    into players values ('N028001122', 'Lateral Direito')
    into players values ('N029112233', 'Ponta Direita')
 
    into players values ('N050223344', 'Defensor')
    into players values ('N051334455', 'Meio-campista')
    into players values ('N052445566', 'Atacante')
    into players values ('N053556677', 'Atacante')
    into players values ('N054667788', 'Meio-campista')
    into players values ('N055778899', 'Meio-campista')
    into players values ('N056889900', 'Atacante')
    into players values ('N057990011', 'Meio-campista')
    into players values ('N058001122', 'Meio-campista')
    into players values ('N059112233', 'Meio-campista')

    into players values ('N060223344', 'Atacante')
    into players values ('N061334455', 'Meio-campista')
    into players values ('N062445566', 'Defensor')
    into players values ('N063556677', 'Atacante')
    into players values ('N064667788', 'Defensor')
    into players values ('N065778899', 'Defensor')
    into players values ('N066889900', 'Atacante')
    into players values ('N067990011', 'Atacante')
    into players values ('N068001122', 'Meio-campista')
    into players values ('N069112233', 'Defensor')

    into players values ('N070223344', 'Meio-campista')
    into players values ('N071334455', 'Atacante')
    into players values ('N072445566', 'Defensor')
    into players values ('N073556677', 'Atacante')
    into players values ('N074667788', 'Meio-campista')
    into players values ('N075778899', 'Defensor')
    into players values ('N076889900', 'Meio-campista')
    into players values ('N077990011', 'Defensor')
    into players values ('N078001122', 'Atacante')
    into players values ('N079112233', 'Meio-campista')
    
    into players values ('N080223344', 'Meio-Campista')
    into players values ('N081334455', 'Atacante')
    into players values ('N082445566', 'Defensor')
    into players values ('N083556677', 'Atacante')
    into players values ('N084667788', 'Defensor')
    into players values ('N085778899', 'Defensor')

    
    
select * from dual;


insert into contracts values ('C0001', get_nipc('Flamengo'), 'N112233445', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0002', get_nipc('Flamengo'), 'N223344556', DATE '2023-01-01', DATE '2026-07-01', 55000);
insert into contracts values ('C0003', get_nipc('Flamengo'), 'N334455667', DATE '2023-01-01', DATE '2026-08-01', 60000);
insert into contracts values ('C0004', get_nipc('Flamengo'), 'N445566778', DATE '2023-01-01', DATE '2026-09-01', 65000);
insert into contracts values ('C0005', get_nipc('Flamengo'), 'N556677889', DATE '2023-01-01', DATE '2026-10-01', 70000);
insert into contracts values ('C0006', get_nipc('Flamengo'), 'N667788990', DATE '2023-01-01', DATE '2026-11-01', 75000);
insert into contracts values ('C0007', get_nipc('Flamengo'), 'N778899001', DATE '2023-01-01', DATE '2026-12-01', 80000);
insert into contracts values ('C0008', get_nipc('Flamengo'), 'N889900112', DATE '2023-01-01', DATE '2026-01-01', 85000);
insert into contracts values ('C0009', get_nipc('Flamengo'), 'N990011223', DATE '2023-01-01', DATE '2026-02-01', 90000);
insert into contracts values ('C0010', get_nipc('Flamengo'), 'N001122334', DATE '2023-01-01', DATE '2026-03-01', 95000);

insert into contracts values ('C0011', get_nipc('Santos'), 'N001223344', DATE '2023-01-01', DATE '2026-06-01', 100000);
insert into contracts values ('C0012', get_nipc('Santos'), 'N002334455', DATE '2023-01-01', DATE '2026-07-01', 110000);
insert into contracts values ('C0013', get_nipc('Santos'), 'N003445566', DATE '2023-01-01', DATE '2026-08-01', 120000);
insert into contracts values ('C0014', get_nipc('Santos'), 'N004556677', DATE '2023-01-01', DATE '2026-09-01', 130000);
insert into contracts values ('C0015', get_nipc('Santos'), 'N005667788', DATE '2023-01-01', DATE '2026-10-01', 140000);
insert into contracts values ('C0016', get_nipc('Santos'), 'N006778899', DATE '2023-01-01', DATE '2026-11-01', 150000);
insert into contracts values ('C0017', get_nipc('Santos'), 'N007889900', DATE '2023-01-01', DATE '2026-12-01', 160000);
insert into contracts values ('C0018', get_nipc('Santos'), 'N008990011', DATE '2023-01-01', DATE '2026-01-01', 170000);
insert into contracts values ('C0019', get_nipc('Santos'), 'N009001122', DATE '2023-01-01', DATE '2026-02-01', 180000);
insert into contracts values ('C0020', get_nipc('Santos'), 'N010112233', DATE '2023-01-01', DATE '2026-03-01', 190000);

insert into contracts values ('C0021', get_nipc('Sao Paulo'), 'N010223344', DATE '2023-01-01', DATE '2026-06-01', 100000);
insert into contracts values ('C0022', get_nipc('Sao Paulo'), 'N011334455', DATE '2023-01-01', DATE '2026-07-01', 110000);
insert into contracts values ('C0023', get_nipc('Sao Paulo'), 'N012445566', DATE '2023-01-01', DATE '2026-08-01', 120000);
insert into contracts values ('C0024', get_nipc('Sao Paulo'), 'N013556677', DATE '2023-01-01', DATE '2026-09-01', 130000);
insert into contracts values ('C0025', get_nipc('Sao Paulo'), 'N014667788', DATE '2023-01-01', DATE '2026-10-01', 140000);
insert into contracts values ('C0026', get_nipc('Sao Paulo'), 'N015778899', DATE '2023-01-01', DATE '2026-11-01', 150000);
insert into contracts values ('C0027', get_nipc('Sao Paulo'), 'N016889900', DATE '2023-01-01', DATE '2026-12-01', 160000);
insert into contracts values ('C0028', get_nipc('Sao Paulo'), 'N017990011', DATE '2023-01-01', DATE '2026-01-01', 170000);
insert into contracts values ('C0029', get_nipc('Sao Paulo'), 'N018001122', DATE '2023-01-01', DATE '2026-02-01', 180000);
insert into contracts values ('C0030', get_nipc('Sao Paulo'), 'N019112233', DATE '2023-01-01', DATE '2026-03-01', 190000);

insert into contracts values ('C0031', get_nipc('Fluminense'), 'N020223344', DATE '2023-01-01', DATE '2026-04-01', 200000);
insert into contracts values ('C0032', get_nipc('Fluminense'), 'N021334455', DATE '2023-01-01', DATE '2026-05-01', 210000);
insert into contracts values ('C0033', get_nipc('Fluminense'), 'N022445566', DATE '2023-01-01', DATE '2026-06-01', 220000);
insert into contracts values ('C0034', get_nipc('Fluminense'), 'N023556677', DATE '2023-01-01', DATE '2026-07-01', 230000);
insert into contracts values ('C0035', get_nipc('Fluminense'), 'N024667788', DATE '2023-01-01', DATE '2026-08-01', 240000);
insert into contracts values ('C0036', get_nipc('Fluminense'), 'N025778899', DATE '2023-01-01', DATE '2026-09-01', 250000);
insert into contracts values ('C0037', get_nipc('Fluminense'), 'N026889900', DATE '2023-01-01', DATE '2026-10-01', 260000);
insert into contracts values ('C0038', get_nipc('Fluminense'), 'N027990011', DATE '2023-01-01', DATE '2026-11-01', 270000);
insert into contracts values ('C0039', get_nipc('Fluminense'), 'N028001122', DATE '2023-01-01', DATE '2026-12-01', 280000);
insert into contracts values ('C0040', get_nipc('Fluminense'), 'N029112233', DATE '2023-01-01', DATE '2026-01-01', 290000);

insert into contracts values ('C0041', get_nipc('Botafogo'), 'N031334455', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0042', get_nipc('Botafogo'), 'N032445566', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0043', get_nipc('Botafogo'), 'N033556677', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0044', get_nipc('Botafogo'), 'N034667788', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0045', get_nipc('Botafogo'), 'N035778899', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0046', get_nipc('Botafogo'), 'N036889900', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0047', get_nipc('Botafogo'), 'N037990011', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0048', get_nipc('Botafogo'), 'N038001122', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0049', get_nipc('Botafogo'), 'N039112233', DATE '2023-01-01', DATE '2026-06-01', 50000);

insert into contracts values ('C0050', get_nipc('Atletico Mineiro'), 'N040223344', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0051', get_nipc('Atletico Mineiro'), 'N041334455', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0052', get_nipc('Atletico Mineiro'), 'N042445566', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0053', get_nipc('Atletico Mineiro'), 'N043556677', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0054', get_nipc('Atletico Mineiro'), 'N044667788', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0055', get_nipc('Atletico Mineiro'), 'N045778899', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0056', get_nipc('Atletico Mineiro'), 'N046889900', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0057', get_nipc('Atletico Mineiro'), 'N047990011', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0058', get_nipc('Atletico Mineiro'), 'N048001122', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0059', get_nipc('Atletico Mineiro'), 'N049112233', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0060', get_nipc('Atletico Mineiro'), 'N030223344', DATE '2023-01-01', DATE '2026-06-01', 50000);

insert into contracts values ('C0061', get_nipc('Gremio'), 'N051334455', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0062', get_nipc('Gremio'), 'N052445566', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0063', get_nipc('Gremio'), 'N053556677', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0064', get_nipc('Gremio'), 'N054667788', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0065', get_nipc('Gremio'), 'N055778899', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0066', get_nipc('Gremio'), 'N056889900', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0067', get_nipc('Gremio'), 'N057990011', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0068', get_nipc('Gremio'), 'N058001122', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0069', get_nipc('Gremio'), 'N059112233', DATE '2023-01-01', DATE '2026-06-01', 50000);

insert into contracts values ('C0070', get_nipc('Internacional'), 'N060223344', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0071', get_nipc('Internacional'), 'N061334455', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0072', get_nipc('Internacional'), 'N062445566', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0073', get_nipc('Internacional'), 'N063556677', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0074', get_nipc('Internacional'), 'N064667788', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0075', get_nipc('Internacional'), 'N065778899', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0076', get_nipc('Internacional'), 'N066889900', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0077', get_nipc('Internacional'), 'N067990011', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0078', get_nipc('Internacional'), 'N068001122', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0079', get_nipc('Internacional'), 'N069112233', DATE '2023-01-01', DATE '2026-06-01', 50000);

insert into contracts values ('C0080', get_nipc('Corinthians'), 'N070223344', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0081', get_nipc('Corinthians'), 'N071334455', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0082', get_nipc('Corinthians'), 'N072445566', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0083', get_nipc('Corinthians'), 'N073556677', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0084', get_nipc('Corinthians'), 'N074667788', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0085', get_nipc('Corinthians'), 'N075778899', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0086', get_nipc('Corinthians'), 'N076889900', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0087', get_nipc('Corinthians'), 'N077990011', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0088', get_nipc('Corinthians'), 'N078001122', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0089', get_nipc('Corinthians'), 'N079112233', DATE '2023-01-01', DATE '2026-06-01', 50000);
insert into contracts values ('C0090', get_nipc('Corinthians'), 'N050223344', DATE '2023-01-01', DATE '2026-06-01', 50000);

-- More than 3 contracts for the same player example
insert into contracts values ('C0091', get_nipc('Botafogo'), 'N050223344', DATE '2020-01-01', DATE '2020-12-31', 50000);
insert into contracts values ('C0092', get_nipc('Flamengo'), 'N050223344', DATE '2021-01-01', DATE '2021-12-31', 50000);
insert into contracts values ('C0093', get_nipc('Santos'), 'N050223344', DATE '2022-01-01', DATE '2022-12-31', 50000);
insert into contracts values ('C0094', get_nipc('Fluminense'), 'N050223344', DATE '2026-06-02', DATE '2027-06-01', 50000);



insert into loaned_to values ('C0040', get_nipc('Vasco'), DATE '2024-01-01', DATE '2025-07-01', 10000);
insert into loaned_to values ('C0041', get_nipc('Botafogo'), DATE '2024-01-15', DATE '2025-07-15', 12000);
insert into loaned_to values ('C0042', get_nipc('Santos'), DATE '2024-01-01', DATE '2025-08-01', 15000);
insert into loaned_to values ('C0043', get_nipc('Corinthians'), DATE '2024-01-15', DATE '2025-08-15', 13000);
insert into loaned_to values ('C0044', get_nipc('Palmeiras'), DATE '2024-01-01', DATE '2025-09-01', 14000);



insert all 
--estadios serie A
	into stadiums values ('Maracana', 78838, 'Rio de Janeiro', 'Av. Pres. Castelo Branco')
	into stadiums values ('Arena Corinthians', 49220, 'Sao Paulo', 'Av. Miguel Ignacio Curi')
	into stadiums values ('Morumbi', 67528, 'Sao Paulo', 'Praça Roberto Gomes Pedrosa')
	into stadiums values ('Allianz Parque', 43747, 'Sao Paulo', 'Av. Francisco Matarazzo')
	into stadiums values ('Sao Januario', 21122, 'Rio de Janeiro', 'Rua General Almerio de Moura')
	into stadiums values ('Nilton Santos', 46827, 'Rio de Janeiro', 'R. Jose dos Reis')
	into stadiums values ('Vila Belmiro', 16750, 'Santos', 'R. Princesa Isabel')
	into stadiums values ('Arena do Gremio', 60540, 'Porto Alegre', 'Av. Padre Leopoldo Brentano')
	into stadiums values ('Beira-Rio', 50200, 'Porto Alegre', 'Av. Padre Cacique')
	into stadiums values ('Mineirao', 61885, 'Belo Horizonte', 'Av. Antônio Abrahao Caram')
    
    into stadiums values ('Arena Fluminense', 22231, 'Rio de Janeiro', 'R. Pinheiro Machado')
    
--estadios serie B
	into stadiums values ('Arena da Baixada', 42307, 'Curitiba', 'R. Buenos Aires')
	into stadiums values ('Couto Pereira', 41376, 'Curitiba', 'Av. Pres. Getulio Vargas')
	into stadiums values ('Fonte Nova', 50000, 'Salvador', 'Ladeira da Fonte das Pedras')
	into stadiums values ('Barradao', 34528, 'Salvador', 'R. Artemio Castro Valente')
	into stadiums values ('Ilha do Retiro', 32960, 'Recife', 'Rua Sport Club do Recife')
	into stadiums values ('Arruda', 60044, 'Recife', 'R. Doutor Jose Augusto Moreira')
	into stadiums values ('Aflitos', 19647, 'Recife', 'Av. Rosa e Silva')
	into stadiums values ('Castelao', 63903, 'Fortaleza', 'Av. Alberto Craveiro')
	into stadiums values ('Serrinha', 12722, 'Goiania', 'Av. Edmundo P. de Abreu')
	into stadiums values ('Serra Dourada', 50000, 'Goiania', 'Av. Fued Jose Sebba')
    
--estadios serie C 
	into stadiums values ('Moises Lucarelli', 17768, 'Campinas', 'R. Cap. Leonidas Marques')
	into stadiums values ('Brinco de Ouro', 29893, 'Campinas', 'Av. Imperatriz Leopoldina')
	into stadiums values ('Anacleto Campanella', 16756, 'Sao Caetano do Sul', 'Rua Walter Tome')
	into stadiums values ('Bruno Jose Daniel', 15726, 'Santo Andre', 'Rua 24 de Maio')
	into stadiums values ('Alfredo Jaconi', 23018, 'Caxias do Sul', 'Rua Hercules Gallo')
	into stadiums values ('Heriberto Hulse', 19974, 'Criciuma', 'R. Treze de Maio')
	into stadiums values ('Arena Joinville', 22916, 'Joinville', 'Rua Inacio Bastos')
	into stadiums values ('Durival Britto', 20604, 'Curitiba', 'R. Eng. Nehring')
	into stadiums values ('Estadio do Cafe', 36045, 'Londrina', 'Av. Henrique Mansano')
	into stadiums values ('Mangueirao', 45423, 'Belem', 'Av. Alm. Barroso')
    
--estadios a mais 
	into stadiums values ('Frasqueirao', 15000, 'Natal', 'Av. Prudente de Morais')
	into stadiums values ('Colosso do Tapajos', 20000, 'Santarem', 'Av. Mendonça Furtado')
	into stadiums values ('Roberto Simonsen', 10000, 'Manaus', 'Av. Constantino Nery')
	into stadiums values ('Nabi Abi Chedid', 15000, 'Braganca Paulista', 'R. Emilio Colela')
select * from dual;

insert all
    
    --rounds championship of 2024 , Serie A   
    
    --round 1
    into matches values ('Maracana', date '2024-05-18', get_nipc('Atletico Mineiro'), get_nipc('Corinthians'), 2, 0, 'Brasileirao A', 2024, 1, 'N123456789')
    into matches values ('Vila Belmiro', date '2024-05-18', get_nipc('Flamengo'), get_nipc('Internacional'), 0, 1, 'Brasileirao A', 2024, 1, 'N987654321')
    into matches values ('Morumbi', date '2024-05-18', get_nipc('Sao Paulo'), get_nipc('Botafogo'), 1, 3, 'Brasileirao A', 2024, 1, 'N123789456')
    into matches values ('Sao Januario', date '2024-05-18', get_nipc('Palmeiras'), get_nipc('Gremio'), 1, 2, 'Brasileirao A', 2024, 1, 'N456123789')
    into matches values ('Arena do Gremio', date '2024-05-18', get_nipc('Santos'), get_nipc('Vasco'), 1, 0, 'Brasileirao A', 2024, 1, 'N654321987')
    
    --round 2
    into matches values ('Beira-Rio', date '2024-05-25', get_nipc('Atletico Mineiro'), get_nipc('Vasco'), 2, 1, 'Brasileirao A', 2024, 2, 'N987654321')
    into matches values ('Allianz Parque', date '2024-05-25', get_nipc('Gremio'), get_nipc('Santos'), 2, 0, 'Brasileirao A', 2024, 2, 'N123456789')
    into matches values ('Arena Corinthians', date '2024-05-25', get_nipc('Botafogo'), get_nipc('Palmeiras'), 1, 0, 'Brasileirao A', 2024, 2, 'N987321654')
    into matches values ('Nilton Santos', date '2024-05-25', get_nipc('Internacional'), get_nipc('Sao Paulo'), 3, 0, 'Brasileirao A', 2024, 2, 'N456123789')
    into matches values ('Mineirao', date '2024-05-25', get_nipc('Corinthians'), get_nipc('Flamengo'), 0, 1, 'Brasileirao A', 2024, 2, 'N456789123')

    --round 3
    into matches values ('Maracana', date '2024-06-08', get_nipc('Palmeiras'), get_nipc('Flamengo'), 5, 4, 'Brasileirao A', 2024, 3, 'N987654321')
    into matches values ('Beira-Rio', date '2024-06-08', get_nipc('Santos'), get_nipc('Corinthians'), 1, 1, 'Brasileirao A', 2024, 3, 'N123456789')
    into matches values ('Morumbi', date '2024-06-08', get_nipc('Vasco'), get_nipc('Internacional'), 0, 4, 'Brasileirao A', 2024, 3, 'N123789456')
    into matches values ('Sao Januario', date '2024-06-08', get_nipc('Gremio'), get_nipc('Botafogo'), 2, 2, 'Brasileirao A', 2024, 3, 'N456123789')
    into matches values ('Arena do Gremio', date '2024-06-08', get_nipc('Atletico Mineiro'), get_nipc('Sao Paulo'), 1, 1, 'Brasileirao A', 2024, 3, 'N456789123')

    
     --round 4 
    into matches values ('Beira-Rio', date '2024-06-15', get_nipc('Atletico Mineiro'), get_nipc('Palmeiras'), 1, 0, 'Brasileirao A', 2024, 4, 'N123456789')
    into matches values ('Allianz Parque', date '2024-06-15', get_nipc('Santos'), get_nipc('Sao Paulo'), 1, 2, 'Brasileirao A', 2024, 4, 'N987654321')
    into matches values ('Arena Corinthians', date '2024-06-15', get_nipc('Vasco'), get_nipc('Flamengo'), 0, 1, 'Brasileirao A', 2024, 4, 'N123789456')
    into matches values ('Nilton Santos', date '2024-06-15', get_nipc('Gremio'), get_nipc('Corinthians'), 1, 0, 'Brasileirao A', 2024, 4, 'N456123789')
    into matches values ('Mineirao', date '2024-06-15', get_nipc('Botafogo'), get_nipc('Internacional'), 3, 0, 'Brasileirao A', 2024, 4, 'N456789123')
    
    --round 5
    into matches values ('Maracana', date '2024-07-20', get_nipc('Atletico Mineiro'), get_nipc('Santos'), 0, 4, 'Brasileirao A', 2024, 5, 'N123456789')
    into matches values ('Vila Belmiro', date '2024-07-20', get_nipc('Vasco'), get_nipc('Palmeiras'), 2, 0, 'Brasileirao A', 2024, 5, 'N987654321')
    into matches values ('Morumbi', date '2024-07-20', get_nipc('Gremio'), get_nipc('Sao Paulo'), 1, 0, 'Brasileirao A', 2024, 5, 'N123789456')
    into matches values ('Sao Januario', date '2024-07-20', get_nipc('Botafogo'), get_nipc('Flamengo'), 1, 1, 'Brasileirao A', 2024, 5, 'N456123789')
    into matches values ('Beira-Rio', date '2024-07-20', get_nipc('Internacional'), get_nipc('Corinthians'), 2, 1, 'Brasileirao A', 2024, 5, 'N456789123')


    -- round 6
    into matches values ('Beira-Rio', date '2024-07-27', get_nipc('Atletico Mineiro'), get_nipc('Gremio'), 0, 2, 'Brasileirao A', 2024, 6, 'N123789456')
    into matches values ('Allianz Parque', date '2024-07-27', get_nipc('Botafogo'), get_nipc('Vasco'), 0, 0, 'Brasileirao A', 2024, 6, 'N456123789')
    into matches values ('Arena Corinthians', date '2024-07-27', get_nipc('Internacional'), get_nipc('Santos'), 2, 2, 'Brasileirao A', 2024, 6, 'N123456789')
    into matches values ('Nilton Santos', date '2024-07-27', get_nipc('Corinthians'), get_nipc('Palmeiras'), 3, 3, 'Brasileirao A', 2024, 6, 'N456789123')
    into matches values ('Maracana', date '2024-07-27', get_nipc('Flamengo'), get_nipc('Sao Paulo'), 1, 1, 'Brasileirao A', 2024, 6, 'N987654321')
    
     --round 7 
    into matches values ('Maracana', date '2024-08-10', get_nipc('Atletico Mineiro'), get_nipc('Botafogo'), 1, 2, 'Brasileirao A', 2024, 7, 'N123456789')
    into matches values ('Vila Belmiro', date '2024-08-10', get_nipc('Internacional'), get_nipc('Gremio'), 2, 3, 'Brasileirao A', 2024, 7, 'N456789123')
    into matches values ('Morumbi', date '2024-08-10', get_nipc('Corinthians'), get_nipc('Vasco'), 0, 2, 'Brasileirao A', 2024, 7, 'N987654321')
    into matches values ('Sao Januario', date '2024-08-10', get_nipc('Flamengo'), get_nipc('Santos'), 1, 0, 'Brasileirao A', 2024, 7, 'N123789456')
    into matches values ('Arena do Gremio', date '2024-08-10', get_nipc('Sao Paulo'), get_nipc('Palmeiras'), 0, 3, 'Brasileirao A', 2024, 7, 'N456123789')
    
   
    --round 8
    into matches values ('Beira-Rio', date '2024-08-17', get_nipc('Atletico Mineiro'), get_nipc('Internacional'), 0, 0, 'Brasileirao A', 2024, 8, 'N123456789')
    into matches values ('Allianz Parque', date '2024-08-17', get_nipc('Corinthians'), get_nipc('Botafogo'), 0, 1, 'Brasileirao A', 2024, 8, 'N987654321')
    into matches values ('Arena Corinthians', date '2024-08-17', get_nipc('Flamengo'), get_nipc('Gremio'), 2, 2, 'Brasileirao A', 2024, 8, 'N123789456')
    into matches values ('Nilton Santos', date '2024-08-17', get_nipc('Sao Paulo'), get_nipc('Vasco'), 3, 2, 'Brasileirao A', 2024, 8, 'N456123789')
    into matches values ('Mineirao', date '2024-08-17', get_nipc('Palmeiras'), get_nipc('Santos'), 1, 0, 'Brasileirao A', 2024, 8, 'N654321987')
    
    --round 9
    into matches values ('Maracana', date '2024-09-24', get_nipc('Atletico Mineiro'), get_nipc('Flamengo'), 0, 0, 'Brasileirao A', 2024, 9, 'N123456789')
    into matches values ('Vila Belmiro', date '2024-09-24', get_nipc('Sao Paulo'), get_nipc('Corinthians'), 2, 0, 'Brasileirao A', 2024, 9, 'N456789123')
    into matches values ('Morumbi', date '2024-09-24', get_nipc('Palmeiras'), get_nipc('Internacional'), 1, 0, 'Brasileirao A', 2024, 9, 'N123789456')
    into matches values ('Sao Januario', date '2024-09-24', get_nipc('Santos'), get_nipc('Botafogo'), 2, 2, 'Brasileirao A', 2024, 9, 'N987654321')
    into matches values ('Nilton Santos', date '2024-09-24', get_nipc('Vasco'), get_nipc('Gremio'), 1, 0, 'Brasileirao A', 2024, 9, 'N456123789')
    
    
    --round 10
    into matches values ('Beira-Rio', date '2024-10-01', get_nipc('Sao Paulo'), get_nipc('Atletico Mineiro'), 3, 4, 'Brasileirao A', 2024, 10, 'N123789456')
    into matches values ('Allianz Parque', date '2024-10-01', get_nipc('Flamengo'), get_nipc('Palmeiras'), 2, 0, 'Brasileirao A', 2024, 10, 'N987321654')
    into matches values ('Arena Corinthians', date '2024-10-01', get_nipc('Corinthians'), get_nipc('Santos'), 1, 0, 'Brasileirao A', 2024, 10, 'N987654321')
    into matches values ( 'Nilton Santos', date '2024-10-01', get_nipc('Internacional'), get_nipc('Vasco'), 0, 2, 'Brasileirao A', 2024, 10, 'N123456789')
    into matches values ('Mineirao', date '2024-10-01', get_nipc('Botafogo'), get_nipc('Gremio'), 3, 2, 'Brasileirao A', 2024, 10, 'N456789123')
    
     --round 11
    into matches values ('Maracana', date '2024-10-08', get_nipc('Santos'), get_nipc('Atletico Mineiro'), 1, 1, 'Brasileirao A', 2024, 11, 'N123456789')
    into matches values ('Allianz Parque', date '2024-10-08', get_nipc('Palmeiras'), get_nipc('Vasco'), 0, 2, 'Brasileirao A', 2024, 11, 'N987654321')
    into matches values ('Morumbi', date '2024-10-08', get_nipc('Sao Paulo'), get_nipc('Gremio'), 1, 0, 'Brasileirao A', 2024, 11, 'N123789456')
    into matches values ('Sao Januario', date '2024-10-08', get_nipc('Flamengo'), get_nipc('Botafogo'), 1, 0, 'Brasileirao A', 2024, 11, 'N456123789')
    into matches values ('Nilton Santos', date '2024-10-08', get_nipc('Corinthians'), get_nipc('Internacional'), 1, 2, 'Brasileirao A', 2024, 11, 'N456789123')
    
    --round 12
    into matches values ('Beira-Rio', date '2024-10-15', get_nipc('Palmeiras'), get_nipc('Atletico Mineiro'), 0, 2, 'Brasileirao A', 2024, 12, 'N123789456')
    into matches values ('Allianz Parque', date '2024-10-15', get_nipc('Sao Paulo'), get_nipc('Santos'), 1, 0, 'Brasileirao A', 2024, 12, 'N456123789')
    into matches values ('Arena Corinthians', date '2024-10-15', get_nipc('Flamengo'), get_nipc('Vasco'), 2, 2, 'Brasileirao A', 2024, 12, 'N123456789')
    into matches values ('Nilton Santos', date '2024-10-15', get_nipc('Corinthians'), get_nipc('Gremio'), 2, 3, 'Brasileirao A', 2024, 12, 'N456789123')
    into matches values ('Mineirao', date '2024-10-15', get_nipc('Internacional'), get_nipc('Botafogo'), 2, 0, 'Brasileirao A', 2024, 12, 'N987654321')
    
    --round 13
    into matches values ('Maracana', date '2024-11-22', get_nipc('Corinthians'), get_nipc('Atletico Mineiro'), 5, 0, 'Brasileirao A', 2024, 13, 'N123456789')
    into matches values ('Vila Belmiro', date '2024-11-22', get_nipc('Internacional'), get_nipc('Flamengo'), 1, 0, 'Brasileirao A', 2024, 13, 'N456789123')
    into matches values ('Morumbi', date '2024-11-22', get_nipc('Botafogo'), get_nipc('Sao Paulo'), 2, 2, 'Brasileirao A', 2024, 13, 'N123789456')
    into matches values ('Sao Januario', date '2024-11-22', get_nipc('Gremio'), get_nipc('Palmeiras'), 2, 3, 'Brasileirao A', 2024, 13, 'N987654321')
    into matches values ('Arena do Gremio', date '2024-11-22', get_nipc('Vasco'), get_nipc('Santos'), 0, 1, 'Brasileirao A', 2024, 13, 'N456123789')
    
    --round 14 
    into matches values ('Beira-Rio', date '2024-11-29', get_nipc('Gremio'), get_nipc('Atletico Mineiro'), 3, 4, 'Brasileirao A', 2024, 14, 'N123789456')
    into matches values ('Allianz Parque', date '2024-11-29', get_nipc('Vasco'), get_nipc('Botafogo'), 2, 1, 'Brasileirao A', 2024, 14, 'N456789123')
    into matches values ('Arena Corinthians', date '2024-11-29', get_nipc('Santos'), get_nipc('Internacional'), 1, 1, 'Brasileirao A', 2024, 14, 'N987654321')
    into matches values ('Nilton Santos', date '2024-11-29', get_nipc('Palmeiras'), get_nipc('Corinthians'), 4, 2, 'Brasileirao A', 2024, 14, 'N123456789')
    into matches values ('Mineirao', date '2024-11-29', get_nipc('Sao Paulo'), get_nipc('Flamengo'), 2, 1, 'Brasileirao A', 2024, 14, 'N456123789')
    
    --round 15
    into matches values ('Maracana', date '2024-12-06', get_nipc('Internacional'), get_nipc('Atletico Mineiro'), 2, 0, 'Brasileirao A', 2024, 15, 'N123456789')
    into matches values ('Vila Belmiro', date '2024-12-06', get_nipc('Botafogo'), get_nipc('Corinthians'), 2, 2, 'Brasileirao A', 2024, 15, 'N987654321')
    into matches values ('Morumbi', date '2024-12-06', get_nipc('Gremio'), get_nipc('Flamengo'), 2, 0, 'Brasileirao A', 2024, 15, 'N123789456')
    into matches values ('Sao Januario', date '2024-12-06', get_nipc('Vasco'), get_nipc('Sao Paulo'), 3, 0, 'Brasileirao A', 2024, 15, 'N456123789')
    into matches values ('Arena do Gremio', date '2024-12-06', get_nipc('Santos'), get_nipc('Palmeiras'), 4, 0, 'Brasileirao A', 2024, 15, 'N456789123')
    
    
    --round 16
    into matches values ('Beira-Rio', date '2024-12-13', get_nipc('Flamengo'), get_nipc('Atletico Mineiro'), 1, 1, 'Brasileirao A', 2024, 16, 'N123789456')
    into matches values ('Allianz Parque', date '2024-12-13', get_nipc('Corinthians'), get_nipc('Sao Paulo'), 3, 4, 'Brasileirao A', 2024, 16, 'N123456789')
    into matches values ('Arena Corinthians', date '2024-12-13', get_nipc('Internacional'), get_nipc('Palmeiras'), 0, 1, 'Brasileirao A', 2024, 16, 'N987654321')
    into matches values ('Nilton Santos', date '2024-12-13', get_nipc('Botafogo'), get_nipc('Santos'), 1, 0, 'Brasileirao A', 2024, 16, 'N456789123')
    into matches values ('Mineirao', date '2024-12-13', get_nipc('Gremio'), get_nipc('Vasco'), 0, 1, 'Brasileirao A', 2024, 16, 'N456123789')
    
    
     --round 17
    into matches values ('Maracana', date '2024-12-20', get_nipc('Botafogo'), get_nipc('Atletico Mineiro'), 3, 0, 'Brasileirao A', 2024, 17, 'N123456789')
    into matches values ('Vila Belmiro', date '2024-12-20', get_nipc('Gremio'), get_nipc('Internacional'), 0, 1, 'Brasileirao A', 2024, 17, 'N456789123')
    into matches values ('Morumbi', date '2024-12-20', get_nipc('Vasco'), get_nipc('Corinthians'), 2, 2, 'Brasileirao A', 2024, 17, 'N123789456')
    into matches values ('Sao Januario', date '2024-12-20', get_nipc('Santos'), get_nipc('Flamengo'), 0, 1, 'Brasileirao A', 2024, 17, 'N987654321')
    into matches values ('Arena do Gremio', date '2024-12-20', get_nipc('Palmeiras'), get_nipc('Sao Paulo'), 0, 0, 'Brasileirao A', 2024, 17, 'N456123789')
    
    --rounds do campeonato brasileiro de 2023 serie A
     --round 1
    into matches values ('Maracana', date '2023-05-18', get_nipc('Atletico Mineiro'), get_nipc('Fluminense'), 2, 0, 'Brasileirao A', 2023, 1, 'N123456789')
    into matches values ('Vila Belmiro', date '2023-05-18', get_nipc('Flamengo'), get_nipc('Internacional'), 0, 1, 'Brasileirao A', 2023, 1, 'N987654321')
    into matches values ('Morumbi', date '2023-05-18', get_nipc('Sao Paulo'), get_nipc('Botafogo'), 1, 1, 'Brasileirao A', 2023, 1, 'N123789456')
    into matches values ('Fonte Nova', date '2023-05-18', get_nipc('Palmeiras'), get_nipc('Bragantino'), 1, 2, 'Brasileirao A', 2023, 1, 'N456123789')
    into matches values ('Arena do Gremio', date '2023-05-18', get_nipc('Santos'), get_nipc('Bahia'), 0, 0, 'Brasileirao A', 2023, 1, 'N654321987')
    
    --round 2
    into matches values ('Beira-Rio', date '2023-05-25', get_nipc('Atletico Mineiro'), get_nipc('Bahia'), 1, 1, 'Brasileirao A', 2023, 2, 'N987654321')
    into matches values ('Allianz Parque', date '2023-05-25', get_nipc('Bragantino'), get_nipc('Santos'), 2, 0, 'Brasileirao A', 2023, 2, 'N123456789')
    into matches values ('Arena Fluminense', date '2023-05-25', get_nipc('Botafogo'), get_nipc('Palmeiras'), 1, 0, 'Brasileirao A', 2023, 2, 'N987321654')
    into matches values ('Nilton Santos', date '2023-05-25', get_nipc('Internacional'), get_nipc('Sao Paulo'), 3, 1, 'Brasileirao A', 2023, 2, 'N456123789')
    into matches values ('Mineirao', date '2023-05-25', get_nipc('Fluminense'), get_nipc('Flamengo'), 0, 1, 'Brasileirao A', 2023, 2, 'N456789123')

    

    --round 3
    into matches values ('Maracana', date '2023-06-08', get_nipc('Palmeiras'), get_nipc('Flamengo'), 1, 4, 'Brasileirao A', 2023, 3, 'N987654321')
    into matches values ('Beira-Rio', date '2023-06-08', get_nipc('Santos'), get_nipc('Fluminense'), 1, 1, 'Brasileirao A', 2023, 3, 'N123456789')
    into matches values ('Morumbi', date '2023-06-08', get_nipc('Bahia'), get_nipc('Internacional'), 2, 0, 'Brasileirao A', 2023, 3, 'N123789456')
    into matches values ('Fonte Nova', date '2023-06-08', get_nipc('Bragantino'), get_nipc('Botafogo'), 0, 2, 'Brasileirao A', 2023, 3, 'N456123789')
    into matches values ('Nabi Abi Chedid', date '2023-06-08', get_nipc('Atletico Mineiro'), get_nipc('Sao Paulo'), 1, 1, 'Brasileirao A', 2023, 3, 'N456789123')

    
     --round 4 
    into matches values ('Beira-Rio', date '2023-06-15', get_nipc('Atletico Mineiro'), get_nipc('Palmeiras'), 0, 0, 'Brasileirao A', 2023, 4, 'N123456789')
    into matches values ('Allianz Parque', date '2023-06-15', get_nipc('Santos'), get_nipc('Sao Paulo'), 1, 2, 'Brasileirao A', 2023, 4, 'N987654321')
    into matches values ('Arena Fluminense', date '2023-06-15', get_nipc('Bahia'), get_nipc('Flamengo'), 0, 1, 'Brasileirao A', 2023, 4, 'N123789456')
    into matches values ('Nilton Santos', date '2023-06-15', get_nipc('Bragantino'), get_nipc('Fluminense'), 1, 0, 'Brasileirao A', 2023, 4, 'N456123789')
    into matches values ('Mineirao', date '2023-06-15', get_nipc('Botafogo'), get_nipc('Internacional'), 3, 0, 'Brasileirao A', 2023, 4, 'N456789123')
    
    
     --round 5
    into matches values ('Maracana', date '2023-07-20', get_nipc('Atletico Mineiro'), get_nipc('Santos'), 0, 1, 'Brasileirao A', 2023, 5, 'N123456789')
    into matches values ('Vila Belmiro', date '2023-07-20', get_nipc('Bahia'), get_nipc('Palmeiras'), 2, 0, 'Brasileirao A', 2023, 5, 'N987654321')
    into matches values ('Morumbi', date '2023-07-20', get_nipc('Bragantino'), get_nipc('Sao Paulo'), 1, 0, 'Brasileirao A', 2023, 5, 'N123789456')
    into matches values ('Fonte Nova', date '2023-07-20', get_nipc('Botafogo'), get_nipc('Flamengo'), 1, 1, 'Brasileirao A', 2023, 5, 'N456123789')
    into matches values ('Beira-Rio', date '2023-07-20', get_nipc('Internacional'), get_nipc('Fluminense'), 0, 1, 'Brasileirao A', 2023, 5, 'N456789123')

    -- round 6
    into matches values ('Beira-Rio', date '2023-07-27', get_nipc('Atletico Mineiro'), get_nipc('Bragantino'), 0, 0, 'Brasileirao A', 2023, 6, 'N123789456')
    into matches values ('Allianz Parque', date '2023-07-27', get_nipc('Botafogo'), get_nipc('Bahia'), 0, 0, 'Brasileirao A', 2023, 6, 'N456123789')
    into matches values ('Arena Fluminense', date '2023-07-27', get_nipc('Internacional'), get_nipc('Santos'), 2, 2, 'Brasileirao A', 2023, 6, 'N123456789')
    into matches values ('Nilton Santos', date '2023-07-27', get_nipc('Fluminense'), get_nipc('Palmeiras'), 5, 3, 'Brasileirao A', 2023, 6, 'N456789123')
    into matches values ('Maracana', date '2023-07-27', get_nipc('Flamengo'), get_nipc('Sao Paulo'), 1, 1, 'Brasileirao A', 2023, 6, 'N987654321')
    
     --round 7 
    into matches values ('Maracana', date '2023-08-10', get_nipc('Atletico Mineiro'), get_nipc('Botafogo'), 0, 3, 'Brasileirao A', 2023, 7, 'N123456789')
    into matches values ('Vila Belmiro', date '2023-08-10', get_nipc('Internacional'), get_nipc('Bragantino'), 2, 2, 'Brasileirao A', 2023, 7, 'N456789123')
    into matches values ('Morumbi', date '2023-08-10', get_nipc('Fluminense'), get_nipc('Bahia'), 0, 0, 'Brasileirao A', 2023, 7, 'N987654321')
    into matches values ('Sao Januario', date '2023-08-10', get_nipc('Flamengo'), get_nipc('Santos'), 1, 0, 'Brasileirao A', 2023, 7, 'N123789456')
    into matches values ('Nabi Abi Chedid', date '2023-08-10', get_nipc('Sao Paulo'), get_nipc('Palmeiras'), 0, 3, 'Brasileirao A', 2023, 7, 'N456123789')
    
    --round 8
    into matches values ('Beira-Rio', date '2023-08-17', get_nipc('Atletico Mineiro'), get_nipc('Internacional'), 1, 0, 'Brasileirao A', 2023, 8, 'N123456789')
    into matches values ('Allianz Parque', date '2023-08-17', get_nipc('Fluminense'), get_nipc('Botafogo'), 0, 1, 'Brasileirao A', 2023, 8, 'N987654321')
    into matches values ('Arena Fluminense', date '2023-08-17', get_nipc('Flamengo'), get_nipc('Bragantino'), 2, 2, 'Brasileirao A', 2023, 8, 'N123789456')
    into matches values ('Nilton Santos', date '2023-08-17', get_nipc('Sao Paulo'), get_nipc('Bahia'), 2, 2, 'Brasileirao A', 2023, 8, 'N456123789')
    into matches values ('Mineirao', date '2023-08-17', get_nipc('Palmeiras'), get_nipc('Santos'), 1, 0, 'Brasileirao A', 2023, 8, 'N654321987')
    
    --round 9
    into matches values ('Maracana', date '2023-09-24', get_nipc('Atletico Mineiro'), get_nipc('Flamengo'), 0, 3, 'Brasileirao A', 2023, 9, 'N123456789')
    into matches values ('Vila Belmiro', date '2023-09-24', get_nipc('Sao Paulo'), get_nipc('Fluminense'), 2, 0, 'Brasileirao A', 2023, 9, 'N456789123')
    into matches values ('Morumbi', date '2023-09-24', get_nipc('Palmeiras'), get_nipc('Internacional'), 0, 4, 'Brasileirao A', 2023, 9, 'N123789456')
    into matches values ('Sao Januario', date '2023-09-24', get_nipc('Santos'), get_nipc('Botafogo'), 2, 2, 'Brasileirao A', 2023, 9, 'N987654321')
    into matches values ('Nilton Santos', date '2023-09-24', get_nipc('Bahia'), get_nipc('Bragantino'), 1, 0, 'Brasileirao A', 2023, 9, 'N456123789')
    
    
    --round 10
    into matches values ('Beira-Rio', date '2023-10-01', get_nipc('Sao Paulo'), get_nipc('Atletico Mineiro'), 3, 0, 'Brasileirao A', 2023, 10, 'N123789456')
    into matches values ('Allianz Parque', date '2023-10-01', get_nipc('Flamengo'), get_nipc('Palmeiras'), 2, 0, 'Brasileirao A', 2023, 10, 'N987321654')
    into matches values ('Arena Fluminense', date '2023-10-01', get_nipc('Fluminense'), get_nipc('Santos'), 1, 0, 'Brasileirao A', 2023, 10, 'N987654321')
    into matches values ( 'Nilton Santos', date '2023-10-01', get_nipc('Internacional'), get_nipc('Bahia'), 0, 2, 'Brasileirao A', 2023, 10, 'N123456789')
    into matches values ('Mineirao', date '2023-10-01', get_nipc('Botafogo'), get_nipc('Bragantino'), 0, 2, 'Brasileirao A', 2023, 10, 'N456789123')
    
    --round 11
    into matches values ('Maracana', date '2023-10-08', get_nipc('Santos'), get_nipc('Atletico Mineiro'), 1, 0, 'Brasileirao A', 2023, 11, 'N123456789')
    into matches values ('Allianz Parque', date '2023-10-08', get_nipc('Palmeiras'), get_nipc('Bahia'), 0, 2, 'Brasileirao A', 2023, 11, 'N987654321')
    into matches values ('Morumbi', date '2023-10-08', get_nipc('Sao Paulo'), get_nipc('Bragantino'), 1, 0, 'Brasileirao A', 2023, 11, 'N123789456')
    into matches values ('Fonte Nova', date '2023-10-08', get_nipc('Flamengo'), get_nipc('Botafogo'), 1, 2, 'Brasileirao A', 2023, 11, 'N456123789')
    into matches values ('Nilton Santos', date '2023-10-08', get_nipc('Fluminense'), get_nipc('Internacional'), 1, 1, 'Brasileirao A', 2023, 11, 'N456789123')
    
    --round 12
    into matches values ('Beira-Rio', date '2023-10-15', get_nipc('Palmeiras'), get_nipc('Atletico Mineiro'), 0, 2, 'Brasileirao A', 2023, 12, 'N123789456')
    into matches values ('Allianz Parque', date '2023-10-15', get_nipc('Sao Paulo'), get_nipc('Santos'), 1, 0, 'Brasileirao A', 2023, 12, 'N456123789')
    into matches values ('Arena Fluminense', date '2023-10-15', get_nipc('Flamengo'), get_nipc('Bahia'), 2, 0, 'Brasileirao A', 2023, 12, 'N123456789')
    into matches values ('Nilton Santos', date '2023-10-15', get_nipc('Fluminense'), get_nipc('Bragantino'), 2, 0, 'Brasileirao A', 2023, 12, 'N456789123')
    into matches values ('Mineirao', date '2023-10-15', get_nipc('Internacional'), get_nipc('Botafogo'), 2, 0, 'Brasileirao A', 2023, 12, 'N987654321')

    --round 13
    into matches values ('Maracana', date '2023-11-22', get_nipc('Fluminense'), get_nipc('Atletico Mineiro'), 3, 2, 'Brasileirao A', 2023, 13, 'N123456789')
    into matches values ('Vila Belmiro', date '2023-11-22', get_nipc('Internacional'), get_nipc('Flamengo'), 1, 2, 'Brasileirao A', 2023, 13, 'N456789123')
    into matches values ('Morumbi', date '2023-11-22', get_nipc('Botafogo'), get_nipc('Sao Paulo'), 2, 2, 'Brasileirao A', 2023, 13, 'N123789456')
    into matches values ('Fonte Nova', date '2023-11-22', get_nipc('Bragantino'), get_nipc('Palmeiras'), 2, 3, 'Brasileirao A', 2023, 13, 'N987654321')
    into matches values ('Nabi Abi Chedid', date '2023-11-22', get_nipc('Bahia'), get_nipc('Santos'), 0, 0, 'Brasileirao A', 2023, 13, 'N456123789')
    
    --round 14 
    into matches values ('Beira-Rio', date '2023-11-29', get_nipc('Bragantino'), get_nipc('Atletico Mineiro'), 3, 3, 'Brasileirao A', 2023, 14, 'N123789456')
    into matches values ('Allianz Parque', date '2023-11-29', get_nipc('Bahia'), get_nipc('Botafogo'), 2, 1, 'Brasileirao A', 2023, 14, 'N456789123')
    into matches values ('Arena Fluminense', date '2023-11-29', get_nipc('Santos'), get_nipc('Internacional'), 1, 1, 'Brasileirao A', 2023, 14, 'N987654321')
    into matches values ('Nilton Santos', date '2023-11-29', get_nipc('Palmeiras'), get_nipc('Fluminense'), 4, 4, 'Brasileirao A', 2023, 14, 'N123456789')
    into matches values ('Mineirao', date '2023-11-29', get_nipc('Sao Paulo'), get_nipc('Flamengo'), 1, 1, 'Brasileirao A', 2023, 14, 'N456123789')
    
    --round 15
    into matches values ('Maracana', date '2023-12-06', get_nipc('Internacional'), get_nipc('Atletico Mineiro'), 2, 0, 'Brasileirao A', 2023, 15, 'N123456789')
    into matches values ('Vila Belmiro', date '2023-12-06', get_nipc('Botafogo'), get_nipc('Fluminense'), 2, 0, 'Brasileirao A', 2023, 15, 'N987654321')
    into matches values ('Morumbi', date '2023-12-06', get_nipc('Bragantino'), get_nipc('Flamengo'), 2, 0, 'Brasileirao A', 2023, 15, 'N123789456')
    into matches values ('Fonte Nova', date '2023-12-06', get_nipc('Bahia'), get_nipc('Sao Paulo'), 3, 0, 'Brasileirao A', 2023, 15, 'N456123789')
    into matches values ('Nabi Abi Chedid', date '2023-12-06', get_nipc('Santos'), get_nipc('Palmeiras'), 4, 0, 'Brasileirao A', 2023, 15, 'N456789123')
    
     --round 16
    into matches values ('Beira-Rio', date '2023-12-13', get_nipc('Flamengo'), get_nipc('Atletico Mineiro'), 1, 1, 'Brasileirao A', 2023, 16, 'N123789456')
    into matches values ('Allianz Parque', date '2023-12-13', get_nipc('Fluminense'), get_nipc('Sao Paulo'), 5, 3, 'Brasileirao A', 2023, 16, 'N123456789')
    into matches values ('Arena Fluminense', date '2023-12-13', get_nipc('Internacional'), get_nipc('Palmeiras'), 0, 0, 'Brasileirao A', 2023, 16, 'N987654321')
    into matches values ('Nilton Santos', date '2023-12-13', get_nipc('Botafogo'), get_nipc('Santos'), 1, 0, 'Brasileirao A', 2023, 16, 'N456789123')
    into matches values ('Mineirao', date '2023-12-13', get_nipc('Bragantino'), get_nipc('Bahia'), 0, 0, 'Brasileirao A', 2023, 16, 'N456123789')
    
    
     --round 17
    into matches values ('Maracana', date '2023-12-20', get_nipc('Botafogo'), get_nipc('Atletico Mineiro'), 2, 0, 'Brasileirao A', 2023, 17, 'N123456789')
    into matches values ('Vila Belmiro', date '2023-12-20', get_nipc('Bragantino'), get_nipc('Internacional'), 0, 3, 'Brasileirao A', 2023, 17, 'N456789123')
    into matches values ('Morumbi', date '2023-12-20', get_nipc('Bahia'), get_nipc('Fluminense'), 2, 2, 'Brasileirao A', 2023, 17, 'N123789456')
    into matches values ('Fonte Nova', date '2023-12-20', get_nipc('Santos'), get_nipc('Flamengo'), 0, 1, 'Brasileirao A', 2023, 17, 'N987654321')
    into matches values ('Nabi Abi Chedid', date '2023-12-20', get_nipc('Palmeiras'), get_nipc('Sao Paulo'), 0, 4, 'Brasileirao A', 2023, 17, 'N456123789')
    
    --rodadas 2022 serie A 
    --round 1
    into matches values ('Estadio do Cafe', date '2022-05-18', get_nipc('Atletico Mineiro'), get_nipc('Fluminense'), 2, 0, 'Brasileirao A', 2022, 1, 'N123456789')
    into matches values ('Vila Belmiro', date '2022-05-18', get_nipc('Londrina'), get_nipc('Goias'), 0, 1, 'Brasileirao A', 2022, 1, 'N987654321')
    into matches values ('Morumbi', date '2022-05-18', get_nipc('Sao Paulo'), get_nipc('Botafogo'), 1, 1, 'Brasileirao A', 2022, 1, 'N123789456')
    into matches values ('Barradao', date '2022-05-18', get_nipc('Palmeiras'), get_nipc('Bragantino'), 1, 2, 'Brasileirao A', 2022, 1, 'N456123789')
    into matches values ('Arena do Gremio', date '2022-05-18', get_nipc('Santos'), get_nipc('Vitoria'), 0, 0, 'Brasileirao A', 2022, 1, 'N654321987')
    
    --round 2
    into matches values ('Serrinha', date '2022-05-25', get_nipc('Atletico Mineiro'), get_nipc('Vitoria'), 1, 1, 'Brasileirao A', 2022, 2, 'N987654321')
    into matches values ('Allianz Parque', date '2022-05-25', get_nipc('Bragantino'), get_nipc('Santos'), 2, 0, 'Brasileirao A', 2022, 2, 'N123456789')
    into matches values ('Arena Fluminense', date '2022-05-25', get_nipc('Botafogo'), get_nipc('Palmeiras'), 1, 0, 'Brasileirao A', 2022, 2, 'N987321654')
    into matches values ('Nilton Santos', date '2022-05-25', get_nipc('Goias'), get_nipc('Sao Paulo'), 3, 0, 'Brasileirao A', 2022, 2, 'N456123789')
    into matches values ('Mineirao', date '2022-05-25', get_nipc('Fluminense'), get_nipc('Londrina'), 0, 1, 'Brasileirao A', 2022, 2, 'N456789123')

    --round 3
    into matches values ('Estadio do Cafe', date '2022-06-08', get_nipc('Palmeiras'), get_nipc('Londrina'), 5, 4, 'Brasileirao A', 2022, 3, 'N987654321')
    into matches values ('Serrinha', date '2022-06-08', get_nipc('Santos'), get_nipc('Fluminense'), 1, 1, 'Brasileirao A', 2022, 3, 'N123456789')
    into matches values ('Morumbi', date '2022-06-08', get_nipc('Vitoria'), get_nipc('Goias'), 0, 0, 'Brasileirao A', 2022, 3, 'N123789456')
    into matches values ('Barradao', date '2022-06-08', get_nipc('Bragantino'), get_nipc('Botafogo'), 0, 2, 'Brasileirao A', 2022, 3, 'N456123789')
    into matches values ('Nabi Abi Chedid', date '2022-06-08', get_nipc('Atletico Mineiro'), get_nipc('Sao Paulo'), 1, 1, 'Brasileirao A', 2022, 3, 'N456789123')

    
     --round 4 
    into matches values ('Serrinha', date '2022-06-15', get_nipc('Atletico Mineiro'), get_nipc('Palmeiras'), 0, 0, 'Brasileirao A', 2022, 4, 'N123456789')
    into matches values ('Allianz Parque', date '2022-06-15', get_nipc('Santos'), get_nipc('Sao Paulo'), 1, 2, 'Brasileirao A', 2022, 4, 'N987654321')
    into matches values ('Arena Fluminense', date '2022-06-15', get_nipc('Vitoria'), get_nipc('Londrina'), 0, 0, 'Brasileirao A', 2022, 4, 'N123789456')
    into matches values ('Nilton Santos', date '2022-06-15', get_nipc('Bragantino'), get_nipc('Fluminense'), 1, 0, 'Brasileirao A', 2022, 4, 'N456123789')
    into matches values ('Mineirao', date '2022-06-15', get_nipc('Botafogo'), get_nipc('Goias'), 3, 0, 'Brasileirao A', 2022, 4, 'N456789123')
    
    --round 5
    into matches values ('Estadio do Cafe', date '2022-07-20', get_nipc('Atletico Mineiro'), get_nipc('Santos'), 0, 0, 'Brasileirao A', 2022, 5, 'N123456789')
    into matches values ('Vila Belmiro', date '2022-07-20', get_nipc('Vitoria'), get_nipc('Palmeiras'), 2, 0, 'Brasileirao A', 2022, 5, 'N987654321')
    into matches values ('Morumbi', date '2022-07-20', get_nipc('Bragantino'), get_nipc('Sao Paulo'), 1, 0, 'Brasileirao A', 2022, 5, 'N123789456')
    into matches values ('Barradao', date '2022-07-20', get_nipc('Botafogo'), get_nipc('Londrina'), 1, 1, 'Brasileirao A', 2022, 5, 'N456123789')
    into matches values ('Serrinha', date '2022-07-20', get_nipc('Goias'), get_nipc('Fluminense'), 0, 1, 'Brasileirao A', 2022, 5, 'N456789123')

    -- round 6
    into matches values ('Serrinha', date '2022-07-27', get_nipc('Atletico Mineiro'), get_nipc('Bragantino'), 0, 0, 'Brasileirao A', 2022, 6, 'N123789456')
    into matches values ('Allianz Parque', date '2022-07-27', get_nipc('Botafogo'), get_nipc('Vitoria'), 0, 0, 'Brasileirao A', 2022, 6, 'N456123789')
    into matches values ('Arena Fluminense', date '2022-07-27', get_nipc('Goias'), get_nipc('Santos'), 2, 2, 'Brasileirao A', 2022, 6, 'N123456789')
    into matches values ('Nilton Santos', date '2022-07-27', get_nipc('Fluminense'), get_nipc('Palmeiras'), 3, 3, 'Brasileirao A', 2022, 6, 'N456789123')
    into matches values ('Estadio do Cafe', date '2022-07-27', get_nipc('Londrina'), get_nipc('Sao Paulo'), 1, 1, 'Brasileirao A', 2022, 6, 'N987654321')

     --round 7 
    into matches values ('Estadio do Cafe', date '2022-08-10', get_nipc('Atletico Mineiro'), get_nipc('Botafogo'), 0, 2, 'Brasileirao A', 2022, 7, 'N123456789')
    into matches values ('Vila Belmiro', date '2022-08-10', get_nipc('Goias'), get_nipc('Bragantino'), 2, 2, 'Brasileirao A', 2022, 7, 'N456789123')
    into matches values ('Morumbi', date '2022-08-10', get_nipc('Fluminense'), get_nipc('Vitoria'), 0, 0, 'Brasileirao A', 2022, 7, 'N987654321')
    into matches values ('Sao Januario', date '2022-08-10', get_nipc('Londrina'), get_nipc('Santos'), 1, 0, 'Brasileirao A', 2022, 7, 'N123789456')
    into matches values ('Nabi Abi Chedid', date '2022-08-10', get_nipc('Sao Paulo'), get_nipc('Palmeiras'), 0, 3, 'Brasileirao A', 2022, 7, 'N456123789')
    
     --round 8
    into matches values ('Serrinha', date '2022-08-17', get_nipc('Atletico Mineiro'), get_nipc('Goias'), 0, 0, 'Brasileirao A', 2022, 8, 'N123456789')
    into matches values ('Allianz Parque', date '2022-08-17', get_nipc('Fluminense'), get_nipc('Botafogo'), 0, 1, 'Brasileirao A', 2022, 8, 'N987654321')
    into matches values ('Arena Fluminense', date '2022-08-17', get_nipc('Londrina'), get_nipc('Bragantino'), 2, 2, 'Brasileirao A', 2022, 8, 'N123789456')
    into matches values ('Nilton Santos', date '2022-08-17', get_nipc('Sao Paulo'), get_nipc('Vitoria'), 2, 2, 'Brasileirao A', 2022, 8, 'N456123789')
    into matches values ('Mineirao', date '2022-08-17', get_nipc('Palmeiras'), get_nipc('Santos'), 1, 0, 'Brasileirao A', 2022, 8, 'N654321987')
    
    --round 9
    into matches values ('Estadio do Cafe', date '2022-09-24', get_nipc('Atletico Mineiro'), get_nipc('Londrina'), 0, 0, 'Brasileirao A', 2022, 9, 'N123456789')
    into matches values ('Vila Belmiro', date '2022-09-24', get_nipc('Sao Paulo'), get_nipc('Fluminense'), 2, 0, 'Brasileirao A', 2022, 9, 'N456789123')
    into matches values ('Morumbi', date '2022-09-24', get_nipc('Palmeiras'), get_nipc('Goias'), 0, 0, 'Brasileirao A', 2022, 9, 'N123789456')
    into matches values ('Sao Januario', date '2022-09-24', get_nipc('Santos'), get_nipc('Botafogo'), 2, 2, 'Brasileirao A', 2022, 9, 'N987654321')
    into matches values ('Nilton Santos', date '2022-09-24', get_nipc('Vitoria'), get_nipc('Bragantino'), 1, 0, 'Brasileirao A', 2022, 9, 'N456123789')
    
    
    --round 10
    into matches values ('Serrinha', date '2022-10-01', get_nipc('Sao Paulo'), get_nipc('Atletico Mineiro'), 3, 0, 'Brasileirao A', 2022, 10, 'N123789456')
    into matches values ('Allianz Parque', date '2022-10-01', get_nipc('Londrina'), get_nipc('Palmeiras'), 2, 0, 'Brasileirao A', 2022, 10, 'N987321654')
    into matches values ('Arena Fluminense', date '2022-10-01', get_nipc('Fluminense'), get_nipc('Santos'), 1, 0, 'Brasileirao A', 2022, 10, 'N987654321')
    into matches values ( 'Nilton Santos', date '2022-10-01', get_nipc('Goias'), get_nipc('Vitoria'), 0, 2, 'Brasileirao A', 2022, 10, 'N123456789')
    into matches values ('Mineirao', date '2022-10-01', get_nipc('Botafogo'), get_nipc('Bragantino'), 0, 2, 'Brasileirao A', 2022, 10, 'N456789123')
    
    
    --round 11
    into matches values ('Estadio do Cafe', date '2022-10-08', get_nipc('Santos'), get_nipc('Atletico Mineiro'), 1, 0, 'Brasileirao A', 2022, 11, 'N123456789')
    into matches values ('Allianz Parque', date '2022-10-08', get_nipc('Palmeiras'), get_nipc('Vitoria'), 0, 2, 'Brasileirao A', 2022, 11, 'N987654321')
    into matches values ('Morumbi', date '2022-10-08', get_nipc('Sao Paulo'), get_nipc('Bragantino'), 1, 0, 'Brasileirao A', 2022, 11, 'N123789456')
    into matches values ('Barradao', date '2022-10-08', get_nipc('Londrina'), get_nipc('Botafogo'), 1, 0, 'Brasileirao A', 2022, 11, 'N456123789')
    into matches values ('Nilton Santos', date '2022-10-08', get_nipc('Fluminense'), get_nipc('Goias'), 1, 1, 'Brasileirao A', 2022, 11, 'N456789123')
    
    --round 12
    into matches values ('Serrinha', date '2022-10-15', get_nipc('Palmeiras'), get_nipc('Atletico Mineiro'), 0, 2, 'Brasileirao A', 2022, 12, 'N123789456')
    into matches values ('Allianz Parque', date '2022-10-15', get_nipc('Sao Paulo'), get_nipc('Santos'), 1, 0, 'Brasileirao A', 2022, 12, 'N456123789')
    into matches values ('Arena Fluminense', date '2022-10-15', get_nipc('Londrina'), get_nipc('Vitoria'), 2, 0, 'Brasileirao A', 2022, 12, 'N123456789')
    into matches values ('Nilton Santos', date '2022-10-15', get_nipc('Fluminense'), get_nipc('Bragantino'), 2, 0, 'Brasileirao A', 2022, 12, 'N456789123')
    into matches values ('Mineirao', date '2022-10-15', get_nipc('Goias'), get_nipc('Botafogo'), 2, 0, 'Brasileirao A', 2022, 12, 'N987654321')
    
    --round 13
    into matches values ('Estadio do Cafe', date '2022-11-22', get_nipc('Fluminense'), get_nipc('Atletico Mineiro'), 5, 0, 'Brasileirao A', 2022, 13, 'N123456789')
    into matches values ('Vila Belmiro', date '2022-11-22', get_nipc('Goias'), get_nipc('Londrina'), 1, 0, 'Brasileirao A', 2022, 13, 'N456789123')
    into matches values ('Morumbi', date '2022-11-22', get_nipc('Botafogo'), get_nipc('Sao Paulo'), 2, 2, 'Brasileirao A', 2022, 13, 'N123789456')
    into matches values ('Barradao', date '2022-11-22', get_nipc('Bragantino'), get_nipc('Palmeiras'), 2, 3, 'Brasileirao A', 2022, 13, 'N987654321')
    into matches values ('Nabi Abi Chedid', date '2022-11-22', get_nipc('Vitoria'), get_nipc('Santos'), 0, 0, 'Brasileirao A', 2022, 13, 'N456123789')
    
    --round 14 
    into matches values ('Serrinha', date '2022-11-29', get_nipc('Bragantino'), get_nipc('Atletico Mineiro'), 3, 3, 'Brasileirao A', 2022, 14, 'N123789456')
    into matches values ('Allianz Parque', date '2022-11-29', get_nipc('Vitoria'), get_nipc('Botafogo'), 2, 1, 'Brasileirao A', 2022, 14, 'N456789123')
    into matches values ('Arena Fluminense', date '2022-11-29', get_nipc('Santos'), get_nipc('Goias'), 1, 1, 'Brasileirao A', 2022, 14, 'N987654321')
    into matches values ('Nilton Santos', date '2022-11-29', get_nipc('Palmeiras'), get_nipc('Fluminense'), 4, 2, 'Brasileirao A', 2022, 14, 'N123456789')
    into matches values ('Mineirao', date '2022-11-29', get_nipc('Sao Paulo'), get_nipc('Londrina'), 1, 1, 'Brasileirao A', 2022, 14, 'N456123789')
    
    --round 15
    into matches values ('Estadio do Cafe', date '2022-12-06', get_nipc('Goias'), get_nipc('Atletico Mineiro'), 2, 0, 'Brasileirao A', 2022, 15, 'N123456789')
    into matches values ('Vila Belmiro', date '2022-12-06', get_nipc('Botafogo'), get_nipc('Fluminense'), 2, 0, 'Brasileirao A', 2022, 15, 'N987654321')
    into matches values ('Morumbi', date '2022-12-06', get_nipc('Bragantino'), get_nipc('Londrina'), 2, 0, 'Brasileirao A', 2022, 15, 'N123789456')
    into matches values ('Barradao', date '2022-12-06', get_nipc('Vitoria'), get_nipc('Sao Paulo'), 3, 0, 'Brasileirao A', 2022, 15, 'N456123789')
    into matches values ('Nabi Abi Chedid', date '2022-12-06', get_nipc('Santos'), get_nipc('Palmeiras'), 4, 0, 'Brasileirao A', 2022, 15, 'N456789123')
    
    
    --round 16
    into matches values ('Serrinha', date '2022-12-13', get_nipc('Londrina'), get_nipc('Atletico Mineiro'), 1, 1, 'Brasileirao A', 2022, 16, 'N123789456')
    into matches values ('Allianz Parque', date '2022-12-13', get_nipc('Fluminense'), get_nipc('Sao Paulo'), 3, 3, 'Brasileirao A', 2022, 16, 'N123456789')
    into matches values ('Arena Fluminense', date '2022-12-13', get_nipc('Goias'), get_nipc('Palmeiras'), 0, 0, 'Brasileirao A', 2022, 16, 'N987654321')
    into matches values ('Nilton Santos', date '2022-12-13', get_nipc('Botafogo'), get_nipc('Santos'), 1, 0, 'Brasileirao A', 2022, 16, 'N456789123')
    into matches values ('Mineirao', date '2022-12-13', get_nipc('Bragantino'), get_nipc('Vitoria'), 0, 0, 'Brasileirao A', 2022, 16, 'N456123789')
    
    
     --round 17
    into matches values ('Estadio do Cafe', date '2022-12-20', get_nipc('Botafogo'), get_nipc('Atletico Mineiro'), 0, 0, 'Brasileirao A', 2022, 17, 'N123456789')
    into matches values ('Vila Belmiro', date '2022-12-20', get_nipc('Bragantino'), get_nipc('Goias'), 0, 0, 'Brasileirao A', 2022, 17, 'N456789123')
    into matches values ('Morumbi', date '2022-12-20', get_nipc('Vitoria'), get_nipc('Fluminense'), 2, 2, 'Brasileirao A', 2022, 17, 'N123789456')
    into matches values ('Barradao', date '2022-12-20', get_nipc('Santos'), get_nipc('Londrina'), 0, 1, 'Brasileirao A', 2022, 17, 'N987654321')
    into matches values ('Nabi Abi Chedid', date '2022-12-20', get_nipc('Palmeiras'), get_nipc('Sao Paulo'), 0, 0, 'Brasileirao A', 2022, 17, 'N456123789')
    
    --Campeonato Brasileirao serie B ano 2024 
    
    --round 1
    into matches values ('Estadio do Cafe', date '2022-05-19', get_nipc('Coritiba'), get_nipc('CRB'), 2, 0, 'Brasileirao B', 2022, 1, 'N123456789')
    into matches values ('Arena da Baixada', date '2022-05-19', get_nipc('Operario'), get_nipc('Vila Nova'), 0, 1, 'Brasileirao B', 2022, 1, 'N987654321')
    into matches values ('Couto Pereira', date '2022-05-19', get_nipc('Mirassol'), get_nipc('Ituano'), 1, 1, 'Brasileirao B', 2022, 1, 'N123789456')
    into matches values ('Barradao', date '2022-05-19', get_nipc('Brusque'), get_nipc('Londrina'), 1, 2, 'Brasileirao B', 2022, 1, 'N456123789')
    into matches values ('Castelao', date '2022-05-19', get_nipc('Novorizontino'), get_nipc('Amazonas'), 0, 0, 'Brasileirao B', 2022, 1, 'N654321987')
    
     --round 2
    into matches values ('Serrinha', date '2022-05-26', get_nipc('Coritiba'), get_nipc('Amazonas'), 1, 1, 'Brasileirao B', 2022, 2, 'N987654321')
    into matches values ('Fonte Nova', date '2022-05-26', get_nipc('Londrina'), get_nipc('Novorizontino'), 2, 0, 'Brasileirao B', 2022, 2, 'N123456789')
    into matches values ('Ilha do Retiro', date '2022-05-26', get_nipc('Ituano'), get_nipc('Brusque'), 1, 0, 'Brasileirao B', 2022, 2, 'N987321654')
    into matches values ('Nilton Santos', date '2022-05-26', get_nipc('Vila Nova'), get_nipc('Mirassol'), 3, 0, 'Brasileirao B', 2022, 2, 'N456123789')
    into matches values ('Serra Dourada', date '2022-05-26', get_nipc('CRB'), get_nipc('Operario'), 0, 1, 'Brasileirao B', 2022, 2, 'N456789123')
    
     --round 3
    into matches values ('Estadio do Cafe', date '2022-06-09', get_nipc('Brusque'), get_nipc('Operario'), 5, 4, 'Brasileirao B', 2022, 3, 'N987654321')
    into matches values ('Serrinha', date '2022-06-09', get_nipc('Novorizontino'), get_nipc('CRB'), 1, 1, 'Brasileirao B', 2022, 3, 'N123456789')
    into matches values ('Couto Pereira', date '2022-06-09', get_nipc('Amazonas'), get_nipc('Vila Nova'), 0, 0, 'Brasileirao B', 2022, 3, 'N123789456')
    into matches values ('Barradao', date '2022-06-09', get_nipc('Londrina'), get_nipc('Ituano'), 0, 2, 'Brasileirao B', 2022, 3, 'N456123789')
    into matches values ('Aflitos', date '2022-06-09', get_nipc('Coritiba'), get_nipc('Mirassol'), 1, 1, 'Brasileirao B', 2022, 3, 'N456789123')
    
       
     --round 4 
    into matches values ('Serrinha', date '2022-06-17', get_nipc('Coritiba'), get_nipc('Brusque'), 0, 0, 'Brasileirao B', 2022, 4, 'N123456789')
    into matches values ('Fonte Nova', date '2022-06-17', get_nipc('Novorizontino'), get_nipc('Mirassol'), 1, 2, 'Brasileirao B', 2022, 4, 'N987654321')
    into matches values ('Ilha do Retiro', date '2022-06-17', get_nipc('Amazonas'), get_nipc('Operario'), 0, 0, 'Brasileirao B', 2022, 4, 'N123789456')
    into matches values ('Nilton Santos', date '2022-06-17', get_nipc('Londrina'), get_nipc('CRB'), 1, 0, 'Brasileirao B', 2022, 4, 'N456123789')
    into matches values ('Serra Dourada', date '2022-06-17', get_nipc('Ituano'), get_nipc('Vila Nova'), 3, 0, 'Brasileirao B', 2022, 4, 'N456789123')
    
    --round 5
    into matches values ('Estadio do Cafe', date '2022-07-23', get_nipc('Coritiba'), get_nipc('Novorizontino'), 0, 0, 'Brasileirao B', 2022, 5, 'N123456789')
    into matches values ('Arena da Baixada', date '2022-07-23', get_nipc('Amazonas'), get_nipc('Brusque'), 2, 0, 'Brasileirao B', 2022, 5, 'N987654321')
    into matches values ('Couto Pereira', date '2022-07-23', get_nipc('Londrina'), get_nipc('Mirassol'), 1, 0, 'Brasileirao B', 2022, 5, 'N123789456')
    into matches values ('Barradao', date '2022-07-23', get_nipc('Ituano'), get_nipc('Operario'), 1, 1, 'Brasileirao B', 2022, 5, 'N456123789')
    into matches values ('Serrinha', date '2022-07-23', get_nipc('Vila Nova'), get_nipc('CRB'), 0, 1, 'Brasileirao B', 2022, 5, 'N456789123')

    -- round 6
    into matches values ('Serrinha', date '2022-07-28', get_nipc('Coritiba'), get_nipc('Londrina'), 0, 0, 'Brasileirao B', 2022, 6, 'N123789456')
    into matches values ('Fonte Nova', date '2022-07-28', get_nipc('Ituano'), get_nipc('Amazonas'), 0, 0, 'Brasileirao B', 2022, 6, 'N456123789')
    into matches values ('Ilha do Retiro', date '2022-07-28', get_nipc('Vila Nova'), get_nipc('Novorizontino'), 2, 2, 'Brasileirao B', 2022, 6, 'N123456789')
    into matches values ('Nilton Santos', date '2022-07-28', get_nipc('CRB'), get_nipc('Brusque'), 3, 3, 'Brasileirao B', 2022, 6, 'N456789123')
    into matches values ('Estadio do Cafe', date '2022-07-28', get_nipc('Operario'), get_nipc('Mirassol'), 1, 1, 'Brasileirao B', 2022, 6, 'N987654321')

     --round 7 
    into matches values ('Estadio do Cafe', date '2022-08-13', get_nipc('Coritiba'), get_nipc('Ituano'), 0, 2, 'Brasileirao B', 2022, 7, 'N123456789')
    into matches values ('Arena da Baixada', date '2022-08-13', get_nipc('Vila Nova'), get_nipc('Londrina'), 2, 2, 'Brasileirao B', 2022, 7, 'N456789123')
    into matches values ('Couto Pereira', date '2022-08-13', get_nipc('CRB'), get_nipc('Amazonas'), 0, 0, 'Brasileirao B', 2022, 7, 'N987654321')
    into matches values ('Sao Januario', date '2022-08-13', get_nipc('Operario'), get_nipc('Novorizontino'), 1, 0, 'Brasileirao B', 2022, 7, 'N123789456')
    into matches values ('Aflitos', date '2022-08-13', get_nipc('Mirassol'), get_nipc('Brusque'), 0, 3, 'Brasileirao B', 2022, 7, 'N456123789')
    
    --round 8
    into matches values ('Serrinha', date '2022-08-18', get_nipc('Coritiba'), get_nipc('Vila Nova'), 0, 0, 'Brasileirao B', 2022, 8, 'N123456789')
    into matches values ('Fonte Nova', date '2022-08-18', get_nipc('CRB'), get_nipc('Ituano'), 0, 1, 'Brasileirao B', 2022, 8, 'N987654321')
    into matches values ('Ilha do Retiro', date '2022-08-18', get_nipc('Operario'), get_nipc('Londrina'), 2, 2, 'Brasileirao B', 2022, 8, 'N123789456')
    into matches values ('Nilton Santos', date '2022-08-18', get_nipc('Mirassol'), get_nipc('Amazonas'), 2, 2, 'Brasileirao B', 2022, 8, 'N456123789')
    into matches values ('Serra Dourada', date '2022-08-18', get_nipc('Brusque'), get_nipc('Novorizontino'), 1, 0, 'Brasileirao B', 2022, 8, 'N654321987')
    
     --round 9
    into matches values ('Estadio do Cafe', date '2022-09-25', get_nipc('Coritiba'), get_nipc('Operario'), 0, 0, 'Brasileirao B', 2022, 9, 'N123456789')
    into matches values ('Arena da Baixada', date '2022-09-25', get_nipc('Mirassol'), get_nipc('CRB'), 2, 0, 'Brasileirao B', 2022, 9, 'N456789123')
    into matches values ('Couto Pereira', date '2022-09-25', get_nipc('Brusque'), get_nipc('Vila Nova'), 0, 0, 'Brasileirao B', 2022, 9, 'N123789456')
    into matches values ('Sao Januario', date '2022-09-25', get_nipc('Novorizontino'), get_nipc('Ituano'), 2, 2, 'Brasileirao B', 2022, 9, 'N987654321')
    into matches values ('Nilton Santos', date '2022-09-25', get_nipc('Amazonas'), get_nipc('Londrina'), 1, 0, 'Brasileirao B', 2022, 9, 'N456123789')
    
    
    --round 10
    into matches values ('Serrinha', date '2022-10-04', get_nipc('Mirassol'), get_nipc('Coritiba'), 3, 0, 'Brasileirao B', 2022, 10, 'N123789456')
    into matches values ('Fonte Nova', date '2022-10-04', get_nipc('Operario'), get_nipc('Brusque'), 2, 0, 'Brasileirao B', 2022, 10, 'N987321654')
    into matches values ('Ilha do Retiro', date '2022-10-04', get_nipc('CRB'), get_nipc('Novorizontino'), 1, 0, 'Brasileirao B', 2022, 10, 'N987654321')
    into matches values ( 'Nilton Santos', date '2022-10-04', get_nipc('Vila Nova'), get_nipc('Amazonas'), 0, 2, 'Brasileirao B', 2022, 10, 'N123456789')
    into matches values ('Serra Dourada', date '2022-10-04', get_nipc('Ituano'), get_nipc('Londrina'), 0, 2, 'Brasileirao B', 2022, 10, 'N456789123')
    
    
    --round 11
    into matches values ('Estadio do Cafe', date '2022-10-09', get_nipc('Novorizontino'), get_nipc('Coritiba'), 1, 0, 'Brasileirao B', 2022, 11, 'N123456789')
    into matches values ('Fonte Nova', date '2022-10-09', get_nipc('Brusque'), get_nipc('Amazonas'), 0, 2, 'Brasileirao B', 2022, 11, 'N987654321')
    into matches values ('Couto Pereira', date '2022-10-09', get_nipc('Mirassol'), get_nipc('Londrina'), 1, 0, 'Brasileirao B', 2022, 11, 'N123789456')
    into matches values ('Barradao', date '2022-10-09', get_nipc('Operario'), get_nipc('Ituano'), 1, 0, 'Brasileirao B', 2022, 11, 'N456123789')
    into matches values ('Nilton Santos', date '2022-10-09', get_nipc('CRB'), get_nipc('Vila Nova'), 1, 1, 'Brasileirao B', 2022, 11, 'N456789123')
    
    --round 12
    into matches values ('Serrinha', date '2022-10-16', get_nipc('Brusque'), get_nipc('Coritiba'), 0, 2, 'Brasileirao B', 2022, 12, 'N123789456')
    into matches values ('Fonte Nova', date '2022-10-16', get_nipc('Mirassol'), get_nipc('Novorizontino'), 1, 0, 'Brasileirao B', 2022, 12, 'N456123789')
    into matches values ('Ilha do Retiro', date '2022-10-16', get_nipc('Operario'), get_nipc('Amazonas'), 2, 0, 'Brasileirao B', 2022, 12, 'N123456789')
    into matches values ('Nilton Santos', date '2022-10-16', get_nipc('CRB'), get_nipc('Londrina'), 2, 0, 'Brasileirao B', 2022, 12, 'N456789123')
    into matches values ('Serra Dourada', date '2022-10-16', get_nipc('Vila Nova'), get_nipc('Ituano'), 2, 0, 'Brasileirao B', 2022, 12, 'N987654321')
    
    --round 13
    into matches values ('Estadio do Cafe', date '2022-11-24', get_nipc('CRB'), get_nipc('Coritiba'), 5, 0, 'Brasileirao B', 2022, 13, 'N123456789')
    into matches values ('Arena da Baixada', date '2022-11-24', get_nipc('Vila Nova'), get_nipc('Operario'), 1, 0, 'Brasileirao B', 2022, 13, 'N456789123')
    into matches values ('Couto Pereira', date '2022-11-24', get_nipc('Ituano'), get_nipc('Mirassol'), 2, 2, 'Brasileirao B', 2022, 13, 'N123789456')
    into matches values ('Barradao', date '2022-11-24', get_nipc('Londrina'), get_nipc('Brusque'), 2, 3, 'Brasileirao B', 2022, 13, 'N987654321')
    into matches values ('Aflitos', date '2022-11-24', get_nipc('Amazonas'), get_nipc('Novorizontino'), 0, 1, 'Brasileirao B', 2022, 13, 'N456123789')
    
    --round 14 
    into matches values ('Serrinha', date '2022-11-26', get_nipc('Londrina'), get_nipc('Coritiba'), 3, 3, 'Brasileirao B', 2022, 14, 'N123789456')
    into matches values ('Fonte Nova', date '2022-11-26', get_nipc('Amazonas'), get_nipc('Ituano'), 2, 1, 'Brasileirao B', 2022, 14, 'N456789123')
    into matches values ('Ilha do Retiro', date '2022-11-26', get_nipc('Novorizontino'), get_nipc('Vila Nova'), 1, 1, 'Brasileirao B', 2022, 14, 'N987654321')
    into matches values ('Nilton Santos', date '2022-11-26', get_nipc('Brusque'), get_nipc('CRB'), 4, 2, 'Brasileirao B', 2022, 14, 'N123456789')
    into matches values ('Serra Dourada', date '2022-11-26', get_nipc('Mirassol'), get_nipc('Operario'), 1, 1, 'Brasileirao B', 2022, 14, 'N456123789')
    
    --round 15
    into matches values ('Estadio do Cafe', date '2022-12-07', get_nipc('Vila Nova'), get_nipc('Coritiba'), 2, 0, 'Brasileirao B', 2022, 15, 'N123456789')
    into matches values ('Arena da Baixada', date '2022-12-07', get_nipc('Ituano'), get_nipc('CRB'), 2, 0, 'Brasileirao B', 2022, 15, 'N987654321')
    into matches values ('Couto Pereira', date '2022-12-07', get_nipc('Londrina'), get_nipc('Operario'), 2, 0, 'Brasileirao B', 2022, 15, 'N123789456')
    into matches values ('Barradao', date '2022-12-07', get_nipc('Amazonas'), get_nipc('Mirassol'), 3, 0, 'Brasileirao B', 2022, 15, 'N456123789')
    into matches values ('Aflitos', date '2022-12-07', get_nipc('Novorizontino'), get_nipc('Brusque'), 4, 0, 'Brasileirao B', 2022, 15, 'N456789123')
    
    
    --round 16
    into matches values ('Serrinha', date '2022-12-15', get_nipc('Operario'), get_nipc('Coritiba'), 1, 1, 'Brasileirao B', 2022, 16, 'N123789456')
    into matches values ('Fonte Nova', date '2022-12-15', get_nipc('CRB'), get_nipc('Mirassol'), 3, 3, 'Brasileirao B', 2022, 16, 'N123456789')
    into matches values ('Ilha do Retiro', date '2022-12-15', get_nipc('Vila Nova'), get_nipc('Brusque'), 0, 0, 'Brasileirao B', 2022, 16, 'N987654321')
    into matches values ('Nilton Santos', date '2022-12-15', get_nipc('Ituano'), get_nipc('Novorizontino'), 1, 0, 'Brasileirao B', 2022, 16, 'N456789123')
    into matches values ('Serra Dourada', date '2022-12-15', get_nipc('Londrina'), get_nipc('Amazonas'), 0, 3, 'Brasileirao B', 2022, 16, 'N456123789')
    
    
     --round 17
    into matches values ('Estadio do Cafe', date '2022-12-23', get_nipc('Ituano'), get_nipc('Coritiba'), 0, 0, 'Brasileirao B', 2022, 17, 'N123456789')
    into matches values ('Arena da Baixada', date '2022-12-23', get_nipc('Londrina'), get_nipc('Vila Nova'), 0, 0, 'Brasileirao B', 2022, 17, 'N456789123')
    into matches values ('Couto Pereira', date '2022-12-23', get_nipc('Amazonas'), get_nipc('CRB'), 2, 2, 'Brasileirao B', 2022, 17, 'N123789456')
    into matches values ('Barradao', date '2022-12-23', get_nipc('Novorizontino'), get_nipc('Operario'), 0, 1, 'Brasileirao B', 2022, 17, 'N987654321')
    into matches values ('Aflitos', date '2022-12-23', get_nipc('Brusque'), get_nipc('Mirassol'), 0, 0, 'Brasileirao B', 2022, 17, 'N456123789')
    
    
    --jogos brasileirao serie B 2023 
    --round 1
    into matches values ('Estadio do Cafe', date '2023-05-19', get_nipc('Coritiba'), get_nipc('CRB'), 2, 0, 'Brasileirao B', 2023, 1, 'N123456789')
    into matches values ('Arena da Baixada', date '2023-05-19', get_nipc('Operario'), get_nipc('Vila Nova'), 0, 1, 'Brasileirao B', 2023, 1, 'N987654321')
    into matches values ('Couto Pereira', date '2023-05-19', get_nipc('Mirassol'), get_nipc('Ituano'), 1, 1, 'Brasileirao B', 2023, 1, 'N123789456')
    into matches values ('Barradao', date '2023-05-19', get_nipc('Brusque'), get_nipc('Londrina'), 1, 2, 'Brasileirao B', 2023, 1, 'N456123789')
    into matches values ('Castelao', date '2023-05-19', get_nipc('America Mineiro'), get_nipc('Amazonas'), 0, 0, 'Brasileirao B', 2023, 1, 'N654321987')
    
     --round 2
    into matches values ('Serrinha', date '2023-05-26', get_nipc('Coritiba'), get_nipc('Amazonas'), 1, 1, 'Brasileirao B', 2023, 2, 'N987654321')
    into matches values ('Fonte Nova', date '2023-05-26', get_nipc('Londrina'), get_nipc('America Mineiro'), 2, 0, 'Brasileirao B', 2023, 2, 'N123456789')
    into matches values ('Ilha do Retiro', date '2023-05-26', get_nipc('Ituano'), get_nipc('Brusque'), 1, 0, 'Brasileirao B', 2023, 2, 'N987321654')
    into matches values ('Arruda', date '2023-05-26', get_nipc('Vila Nova'), get_nipc('Mirassol'), 3, 0, 'Brasileirao B', 2023, 2, 'N456123789')
    into matches values ('Serra Dourada', date '2023-05-26', get_nipc('CRB'), get_nipc('Operario'), 0, 1, 'Brasileirao B', 2023, 2, 'N456789123')
    
     --round 3
    into matches values ('Estadio do Cafe', date '2023-06-09', get_nipc('Brusque'), get_nipc('Operario'), 5, 4, 'Brasileirao B', 2023, 3, 'N987654321')
    into matches values ('Serrinha', date '2023-06-09', get_nipc('America Mineiro'), get_nipc('CRB'), 1, 1, 'Brasileirao B', 2023, 3, 'N123456789')
    into matches values ('Couto Pereira', date '2023-06-09', get_nipc('Amazonas'), get_nipc('Vila Nova'), 0, 0, 'Brasileirao B', 2023, 3, 'N123789456')
    into matches values ('Barradao', date '2023-06-09', get_nipc('Londrina'), get_nipc('Ituano'), 0, 2, 'Brasileirao B', 2023, 3, 'N456123789')
    into matches values ('Aflitos', date '2023-06-09', get_nipc('Coritiba'), get_nipc('Mirassol'), 1, 1, 'Brasileirao B', 2023, 3, 'N456789123')

    
     --round 4 
    into matches values ('Serrinha', date '2023-06-17', get_nipc('Coritiba'), get_nipc('Brusque'), 0, 0, 'Brasileirao B', 2023, 4, 'N123456789')
    into matches values ('Fonte Nova', date '2023-06-17', get_nipc('America Mineiro'), get_nipc('Mirassol'), 1, 2, 'Brasileirao B', 2023, 4, 'N987654321')
    into matches values ('Ilha do Retiro', date '2023-06-17', get_nipc('Amazonas'), get_nipc('Operario'), 0, 0, 'Brasileirao B', 2023, 4, 'N123789456')
    into matches values ('Arruda', date '2023-06-17', get_nipc('Londrina'), get_nipc('CRB'), 1, 0, 'Brasileirao B', 2023, 4, 'N456123789')
    into matches values ('Serra Dourada', date '2023-06-17', get_nipc('Ituano'), get_nipc('Vila Nova'), 3, 0, 'Brasileirao B', 2023, 4, 'N456789123')
    
    --round 5
    into matches values ('Estadio do Cafe', date '2023-07-23', get_nipc('Coritiba'), get_nipc('America Mineiro'), 0, 0, 'Brasileirao B', 2023, 5, 'N123456789')
    into matches values ('Arena da Baixada', date '2023-07-23', get_nipc('Amazonas'), get_nipc('Brusque'), 2, 0, 'Brasileirao B', 2023, 5, 'N987654321')
    into matches values ('Couto Pereira', date '2023-07-23', get_nipc('Londrina'), get_nipc('Mirassol'), 1, 0, 'Brasileirao B', 2023, 5, 'N123789456')
    into matches values ('Barradao', date '2023-07-23', get_nipc('Ituano'), get_nipc('Operario'), 1, 1, 'Brasileirao B', 2023, 5, 'N456123789')
    into matches values ('Serrinha', date '2023-07-23', get_nipc('Vila Nova'), get_nipc('CRB'), 0, 1, 'Brasileirao B', 2023, 5, 'N456789123')
    
    -- round 6
    into matches values ('Serrinha', date '2023-07-28', get_nipc('Coritiba'), get_nipc('Londrina'), 0, 0, 'Brasileirao B', 2023, 6, 'N123789456')
    into matches values ('Fonte Nova', date '2023-07-28', get_nipc('Ituano'), get_nipc('Amazonas'), 0, 0, 'Brasileirao B', 2023, 6, 'N456123789')
    into matches values ('Ilha do Retiro', date '2023-07-28', get_nipc('Vila Nova'), get_nipc('America Mineiro'), 2, 2, 'Brasileirao B', 2023, 6, 'N123456789')
    into matches values ('Arruda', date '2023-07-28', get_nipc('CRB'), get_nipc('Brusque'), 3, 3, 'Brasileirao B', 2023, 6, 'N456789123')
    into matches values ('Estadio do Cafe', date '2023-07-28', get_nipc('Operario'), get_nipc('Mirassol'), 1, 1, 'Brasileirao B', 2023, 6, 'N987654321')
 
     --round 7 
    into matches values ('Estadio do Cafe', date '2023-08-13', get_nipc('Coritiba'), get_nipc('Ituano'), 0, 2, 'Brasileirao B', 2023, 7, 'N123456789')
    into matches values ('Arena da Baixada', date '2023-08-13', get_nipc('Vila Nova'), get_nipc('Londrina'), 2, 2, 'Brasileirao B', 2023, 7, 'N456789123')
    into matches values ('Couto Pereira', date '2023-08-13', get_nipc('CRB'), get_nipc('Amazonas'), 0, 0, 'Brasileirao B', 2023, 7, 'N987654321')
    into matches values ('Sao Januario', date '2023-08-13', get_nipc('Operario'), get_nipc('America Mineiro'), 1, 0, 'Brasileirao B', 2023, 7, 'N123789456')
    into matches values ('Aflitos', date '2023-08-13', get_nipc('Mirassol'), get_nipc('Brusque'), 0, 3, 'Brasileirao B', 2023, 7, 'N456123789')
    
    --round 8
    into matches values ('Serrinha', date '2023-08-18', get_nipc('Coritiba'), get_nipc('Vila Nova'), 0, 0, 'Brasileirao B', 2023, 8, 'N123456789')
    into matches values ('Fonte Nova', date '2023-08-18', get_nipc('CRB'), get_nipc('Ituano'), 0, 1, 'Brasileirao B', 2023, 8, 'N987654321')
    into matches values ('Ilha do Retiro', date '2023-08-18', get_nipc('Operario'), get_nipc('Londrina'), 2, 2, 'Brasileirao B', 2023, 8, 'N123789456')
    into matches values ('Arruda', date '2023-08-18', get_nipc('Mirassol'), get_nipc('Amazonas'), 2, 2, 'Brasileirao B', 2023, 8, 'N456123789')
    into matches values ('Serra Dourada', date '2023-08-18', get_nipc('Brusque'), get_nipc('America Mineiro'), 1, 0, 'Brasileirao B', 2023, 8, 'N654321987')
    
    --round 9
    into matches values ('Estadio do Cafe', date '2023-09-25', get_nipc('Coritiba'), get_nipc('Operario'), 0, 0, 'Brasileirao B', 2023, 9, 'N123456789')
    into matches values ('Arena da Baixada', date '2023-09-25', get_nipc('Mirassol'), get_nipc('CRB'), 2, 0, 'Brasileirao B', 2023, 9, 'N456789123')
    into matches values ('Couto Pereira', date '2023-09-25', get_nipc('Brusque'), get_nipc('Vila Nova'), 0, 0, 'Brasileirao B', 2023, 9, 'N123789456')
    into matches values ('Sao Januario', date '2023-09-25', get_nipc('America Mineiro'), get_nipc('Ituano'), 2, 2, 'Brasileirao B', 2023, 9, 'N987654321')
    into matches values ('Arruda', date '2023-09-25', get_nipc('Amazonas'), get_nipc('Londrina'), 1, 0, 'Brasileirao B', 2023, 9, 'N456123789')
    
    
    --round 10
    into matches values ('Serrinha', date '2023-10-04', get_nipc('Mirassol'), get_nipc('Coritiba'), 3, 0, 'Brasileirao B', 2023, 10, 'N123789456')
    into matches values ('Fonte Nova', date '2023-10-04', get_nipc('Operario'), get_nipc('Brusque'), 2, 0, 'Brasileirao B', 2023, 10, 'N987321654')
    into matches values ('Ilha do Retiro', date '2023-10-04', get_nipc('CRB'), get_nipc('America Mineiro'), 1, 0, 'Brasileirao B', 2023, 10, 'N987654321')
    into matches values ( 'Arruda', date '2023-10-04', get_nipc('Vila Nova'), get_nipc('Amazonas'), 0, 2, 'Brasileirao B', 2023, 10, 'N123456789')
    into matches values ('Serra Dourada', date '2023-10-04', get_nipc('Ituano'), get_nipc('Londrina'), 0, 2, 'Brasileirao B', 2023, 10, 'N456789123')
    
    --round 11
    into matches values ('Estadio do Cafe', date '2023-10-09', get_nipc('America Mineiro'), get_nipc('Coritiba'), 1, 0, 'Brasileirao B', 2023, 11, 'N123456789')
    into matches values ('Fonte Nova', date '2023-10-09', get_nipc('Brusque'), get_nipc('Amazonas'), 0, 2, 'Brasileirao B', 2023, 11, 'N987654321')
    into matches values ('Couto Pereira', date '2023-10-09', get_nipc('Mirassol'), get_nipc('Londrina'), 1, 0, 'Brasileirao B', 2023, 11, 'N123789456')
    into matches values ('Barradao', date '2023-10-09', get_nipc('Operario'), get_nipc('Ituano'), 1, 0, 'Brasileirao B', 2023, 11, 'N456123789')
    into matches values ('Arruda', date '2023-10-09', get_nipc('CRB'), get_nipc('Vila Nova'), 1, 1, 'Brasileirao B', 2023, 11, 'N456789123')
    
    --round 12
    into matches values ('Serrinha', date '2023-10-16', get_nipc('Brusque'), get_nipc('Coritiba'), 0, 2, 'Brasileirao B', 2023, 12, 'N123789456')
    into matches values ('Fonte Nova', date '2023-10-16', get_nipc('Mirassol'), get_nipc('America Mineiro'), 1, 0, 'Brasileirao B', 2023, 12, 'N456123789')
    into matches values ('Ilha do Retiro', date '2023-10-16', get_nipc('Operario'), get_nipc('Amazonas'), 2, 0, 'Brasileirao B', 2023, 12, 'N123456789')
    into matches values ('Arruda', date '2023-10-16', get_nipc('CRB'), get_nipc('Londrina'), 2, 0, 'Brasileirao B', 2023, 12, 'N456789123')
    into matches values ('Serra Dourada', date '2023-10-16', get_nipc('Vila Nova'), get_nipc('Ituano'), 2, 0, 'Brasileirao B', 2023, 12, 'N987654321')
    
    --round 13
    into matches values ('Estadio do Cafe', date '2023-11-24', get_nipc('CRB'), get_nipc('Coritiba'), 5, 0, 'Brasileirao B', 2023, 13, 'N123456789')
    into matches values ('Arena da Baixada', date '2023-11-24', get_nipc('Vila Nova'), get_nipc('Operario'), 1, 0, 'Brasileirao B', 2023, 13, 'N456789123')
    into matches values ('Couto Pereira', date '2023-11-24', get_nipc('Ituano'), get_nipc('Mirassol'), 2, 2, 'Brasileirao B', 2023, 13, 'N123789456')
    into matches values ('Barradao', date '2023-11-24', get_nipc('Londrina'), get_nipc('Brusque'), 2, 3, 'Brasileirao B', 2023, 13, 'N987654321')
    into matches values ('Aflitos', date '2023-11-24', get_nipc('Amazonas'), get_nipc('America Mineiro'), 0, 0, 'Brasileirao B', 2023, 13, 'N456123789')
    
    --round 14 
    into matches values ('Serrinha', date '2023-11-26', get_nipc('Londrina'), get_nipc('Coritiba'), 3, 3, 'Brasileirao B', 2023, 14, 'N123789456')
    into matches values ('Fonte Nova', date '2023-11-26', get_nipc('Amazonas'), get_nipc('Ituano'), 2, 1, 'Brasileirao B', 2023, 14, 'N456789123')
    into matches values ('Ilha do Retiro', date '2023-11-26', get_nipc('America Mineiro'), get_nipc('Vila Nova'), 1, 1, 'Brasileirao B', 2023, 14, 'N987654321')
    into matches values ('Arruda', date '2023-11-26', get_nipc('Brusque'), get_nipc('CRB'), 4, 2, 'Brasileirao B', 2023, 14, 'N123456789')
    into matches values ('Serra Dourada', date '2023-11-26', get_nipc('Mirassol'), get_nipc('Operario'), 1, 1, 'Brasileirao B', 2023, 14, 'N456123789')
    
    --round 15
    into matches values ('Estadio do Cafe', date '2023-12-07', get_nipc('Vila Nova'), get_nipc('Coritiba'), 2, 0, 'Brasileirao B', 2023, 15, 'N123456789')
    into matches values ('Arena da Baixada', date '2023-12-07', get_nipc('Ituano'), get_nipc('CRB'), 2, 0, 'Brasileirao B', 2023, 15, 'N987654321')
    into matches values ('Couto Pereira', date '2023-12-07', get_nipc('Londrina'), get_nipc('Operario'), 2, 0, 'Brasileirao B', 2023, 15, 'N123789456')
    into matches values ('Barradao', date '2023-12-07', get_nipc('Amazonas'), get_nipc('Mirassol'), 3, 0, 'Brasileirao B', 2023, 15, 'N456123789')
    into matches values ('Aflitos', date '2023-12-07', get_nipc('America Mineiro'), get_nipc('Brusque'), 4, 0, 'Brasileirao B', 2023, 15, 'N456789123')
    
    
    --round 16
    into matches values ('Serrinha', date '2023-12-15', get_nipc('Operario'), get_nipc('Coritiba'), 1, 1, 'Brasileirao B', 2023, 16, 'N123789456')
    into matches values ('Fonte Nova', date '2023-12-15', get_nipc('CRB'), get_nipc('Mirassol'), 3, 3, 'Brasileirao B', 2023, 16, 'N123456789')
    into matches values ('Ilha do Retiro', date '2023-12-15', get_nipc('Vila Nova'), get_nipc('Brusque'), 0, 0, 'Brasileirao B', 2023, 16, 'N987654321')
    into matches values ('Arruda', date '2023-12-15', get_nipc('Ituano'), get_nipc('America Mineiro'), 1, 0, 'Brasileirao B', 2023, 16, 'N456789123')
    into matches values ('Serra Dourada', date '2023-12-15', get_nipc('Londrina'), get_nipc('Amazonas'), 0, 0, 'Brasileirao B', 2023, 16, 'N456123789')
    
    
     --round 17
    into matches values ('Estadio do Cafe', date '2023-12-23', get_nipc('Ituano'), get_nipc('Coritiba'), 0, 0, 'Brasileirao B', 2023, 17, 'N123456789')
    into matches values ('Arena da Baixada', date '2023-12-23', get_nipc('Londrina'), get_nipc('Vila Nova'), 0, 0, 'Brasileirao B', 2023, 17, 'N456789123')
    into matches values ('Couto Pereira', date '2023-12-23', get_nipc('Amazonas'), get_nipc('CRB'), 2, 2, 'Brasileirao B', 2023, 17, 'N123789456')
    into matches values ('Barradao', date '2023-12-23', get_nipc('America Mineiro'), get_nipc('Operario'), 0, 1, 'Brasileirao B', 2023, 17, 'N987654321')
    into matches values ('Aflitos', date '2023-12-23', get_nipc('Brusque'), get_nipc('Mirassol'), 0, 0, 'Brasileirao B', 2023, 17, 'N456123789')
    
    --rodadas campeonato serie B 2024 
    --round 1
    into matches values ('Estadio do Cafe', date '2024-05-19', get_nipc('Coritiba'), get_nipc('CRB'), 2, 0, 'Brasileirao B', 2024, 1, 'N123456789')
    into matches values ('Arena da Baixada', date '2024-05-19', get_nipc('Operario'), get_nipc('Cuiaba'), 0, 1, 'Brasileirao B', 2024, 1, 'N987654321')
    into matches values ('Couto Pereira', date '2024-05-19', get_nipc('Mirassol'), get_nipc('Ituano'), 1, 1, 'Brasileirao B', 2024, 1, 'N123789456')
    into matches values ('Barradao', date '2024-05-19', get_nipc('Brusque'), get_nipc('Londrina'), 1, 2, 'Brasileirao B', 2024, 1, 'N456123789')
    into matches values ('Castelao', date '2024-05-19', get_nipc('America Mineiro'), get_nipc('Amazonas'), 0, 0, 'Brasileirao B', 2024, 1, 'N654321987')
    
     --round 2
    into matches values ('Serrinha', date '2024-05-26', get_nipc('Coritiba'), get_nipc('Amazonas'), 1, 1, 'Brasileirao B', 2024, 2, 'N987654321')
    into matches values ('Fonte Nova', date '2024-05-26', get_nipc('Londrina'), get_nipc('America Mineiro'), 2, 0, 'Brasileirao B', 2024, 2, 'N123456789')
    into matches values ('Ilha do Retiro', date '2024-05-26', get_nipc('Ituano'), get_nipc('Brusque'), 1, 0, 'Brasileirao B', 2024, 2, 'N987321654')
    into matches values ('Arruda', date '2024-05-26', get_nipc('Cuiaba'), get_nipc('Mirassol'), 3, 0, 'Brasileirao B', 2024, 2, 'N456123789')
    into matches values ('Serra Dourada', date '2024-05-26', get_nipc('CRB'), get_nipc('Operario'), 0, 1, 'Brasileirao B', 2024, 2, 'N456789123')
    
     --round 3
    into matches values ('Estadio do Cafe', date '2024-06-09', get_nipc('Brusque'), get_nipc('Operario'), 5, 4, 'Brasileirao B', 2024, 3, 'N987654321')
    into matches values ('Serrinha', date '2024-06-09', get_nipc('America Mineiro'), get_nipc('CRB'), 1, 1, 'Brasileirao B', 2024, 3, 'N123456789')
    into matches values ('Couto Pereira', date '2024-06-09', get_nipc('Amazonas'), get_nipc('Cuiaba'), 0, 0, 'Brasileirao B', 2024, 3, 'N123789456')
    into matches values ('Barradao', date '2024-06-09', get_nipc('Londrina'), get_nipc('Ituano'), 0, 2, 'Brasileirao B', 2024, 3, 'N456123789')
    into matches values ('Aflitos', date '2024-06-09', get_nipc('Coritiba'), get_nipc('Mirassol'), 1, 1, 'Brasileirao B', 2024, 3, 'N456789123')

    
     --round 4 
    into matches values ('Serrinha', date '2024-06-17', get_nipc('Coritiba'), get_nipc('Brusque'), 0, 0, 'Brasileirao B', 2024, 4, 'N123456789')
    into matches values ('Fonte Nova', date '2024-06-17', get_nipc('America Mineiro'), get_nipc('Mirassol'), 1, 2, 'Brasileirao B', 2024, 4, 'N987654321')
    into matches values ('Ilha do Retiro', date '2024-06-17', get_nipc('Amazonas'), get_nipc('Operario'), 0, 0, 'Brasileirao B', 2024, 4, 'N123789456')
    into matches values ('Arruda', date '2024-06-17', get_nipc('Londrina'), get_nipc('CRB'), 1, 0, 'Brasileirao B', 2024, 4, 'N456123789')
    into matches values ('Serra Dourada', date '2024-06-17', get_nipc('Ituano'), get_nipc('Cuiaba'), 3, 0, 'Brasileirao B', 2024, 4, 'N456789123')
    
    --round 5
    into matches values ('Estadio do Cafe', date '2024-07-23', get_nipc('Coritiba'), get_nipc('America Mineiro'), 0, 0, 'Brasileirao B', 2024, 5, 'N123456789')
    into matches values ('Arena da Baixada', date '2024-07-23', get_nipc('Amazonas'), get_nipc('Brusque'), 2, 0, 'Brasileirao B', 2024, 5, 'N987654321')
    into matches values ('Couto Pereira', date '2024-07-23', get_nipc('Londrina'), get_nipc('Mirassol'), 1, 0, 'Brasileirao B', 2024, 5, 'N123789456')
    into matches values ('Barradao', date '2024-07-23', get_nipc('Ituano'), get_nipc('Operario'), 1, 1, 'Brasileirao B', 2024, 5, 'N456123789')
    into matches values ('Serrinha', date '2024-07-23', get_nipc('Cuiaba'), get_nipc('CRB'), 0, 1, 'Brasileirao B', 2024, 5, 'N456789123')
    
    -- round 6
    into matches values ('Serrinha', date '2024-07-28', get_nipc('Coritiba'), get_nipc('Londrina'), 0, 0, 'Brasileirao B', 2024, 6, 'N123789456')
    into matches values ('Fonte Nova', date '2024-07-28', get_nipc('Ituano'), get_nipc('Amazonas'), 0, 0, 'Brasileirao B', 2024, 6, 'N456123789')
    into matches values ('Ilha do Retiro', date '2024-07-28', get_nipc('Cuiaba'), get_nipc('America Mineiro'), 2, 2, 'Brasileirao B', 2024, 6, 'N123456789')
    into matches values ('Arruda', date '2024-07-28', get_nipc('CRB'), get_nipc('Brusque'), 3, 3, 'Brasileirao B', 2024, 6, 'N456789123')
    into matches values ('Estadio do Cafe', date '2024-07-28', get_nipc('Operario'), get_nipc('Mirassol'), 1, 1, 'Brasileirao B', 2024, 6, 'N987654321')
    
     --round 7 
    into matches values ('Estadio do Cafe', date '2024-08-13', get_nipc('Coritiba'), get_nipc('Ituano'), 0, 2, 'Brasileirao B', 2024, 7, 'N123456789')
    into matches values ('Arena da Baixada', date '2024-08-13', get_nipc('Cuiaba'), get_nipc('Londrina'), 2, 2, 'Brasileirao B', 2024, 7, 'N456789123')
    into matches values ('Couto Pereira', date '2024-08-13', get_nipc('CRB'), get_nipc('Amazonas'), 0, 0, 'Brasileirao B', 2024, 7, 'N987654321')
    into matches values ('Sao Januario', date '2024-08-13', get_nipc('Operario'), get_nipc('America Mineiro'), 1, 0, 'Brasileirao B', 2024, 7, 'N123789456')
    into matches values ('Aflitos', date '2024-08-13', get_nipc('Mirassol'), get_nipc('Brusque'), 0, 3, 'Brasileirao B', 2024, 7, 'N456123789')
    
    --round 8
    into matches values ('Serrinha', date '2024-08-18', get_nipc('Coritiba'), get_nipc('Cuiaba'), 0, 0, 'Brasileirao B', 2024, 8, 'N123456789')
    into matches values ('Fonte Nova', date '2024-08-18', get_nipc('CRB'), get_nipc('Ituano'), 0, 1, 'Brasileirao B', 2024, 8, 'N987654321')
    into matches values ('Ilha do Retiro', date '2024-08-18', get_nipc('Operario'), get_nipc('Londrina'), 2, 2, 'Brasileirao B', 2024, 8, 'N123789456')
    into matches values ('Arruda', date '2024-08-18', get_nipc('Mirassol'), get_nipc('Amazonas'), 2, 2, 'Brasileirao B', 2024, 8, 'N456123789')
    into matches values ('Serra Dourada', date '2024-08-18', get_nipc('Brusque'), get_nipc('America Mineiro'), 1, 0, 'Brasileirao B', 2024, 8, 'N654321987')
    
    --round 9
    into matches values ('Estadio do Cafe', date '2024-09-25', get_nipc('Coritiba'), get_nipc('Operario'), 0, 0, 'Brasileirao B', 2024, 9, 'N123456789')
    into matches values ('Arena da Baixada', date '2024-09-25', get_nipc('Mirassol'), get_nipc('CRB'), 2, 0, 'Brasileirao B', 2024, 9, 'N456789123')
    into matches values ('Couto Pereira', date '2024-09-25', get_nipc('Brusque'), get_nipc('Cuiaba'), 0, 0, 'Brasileirao B', 2024, 9, 'N123789456')
    into matches values ('Sao Januario', date '2024-09-25', get_nipc('America Mineiro'), get_nipc('Ituano'), 2, 2, 'Brasileirao B', 2024, 9, 'N987654321')
    into matches values ('Arruda', date '2024-09-25', get_nipc('Amazonas'), get_nipc('Londrina'), 1, 0, 'Brasileirao B', 2024, 9, 'N456123789')
    
    
    --round 10
    into matches values ('Serrinha', date '2024-10-04', get_nipc('Mirassol'), get_nipc('Coritiba'), 3, 0, 'Brasileirao B', 2024, 10, 'N123789456')
    into matches values ('Fonte Nova', date '2024-10-04', get_nipc('Operario'), get_nipc('Brusque'), 2, 0, 'Brasileirao B', 2024, 10, 'N987321654')
    into matches values ('Ilha do Retiro', date '2024-10-04', get_nipc('CRB'), get_nipc('America Mineiro'), 1, 0, 'Brasileirao B', 2024, 10, 'N987654321')
    into matches values ( 'Arruda', date '2024-10-04', get_nipc('Cuiaba'), get_nipc('Amazonas'), 0, 2, 'Brasileirao B', 2024, 10, 'N123456789')
    into matches values ('Serra Dourada', date '2024-10-04', get_nipc('Ituano'), get_nipc('Londrina'), 0, 2, 'Brasileirao B', 2024, 10, 'N456789123')
    
    --round 11
    into matches values ('Estadio do Cafe', date '2024-10-09', get_nipc('America Mineiro'), get_nipc('Coritiba'), 1, 0, 'Brasileirao B', 2024, 11, 'N123456789')
    into matches values ('Fonte Nova', date '2024-10-09', get_nipc('Brusque'), get_nipc('Amazonas'), 0, 2, 'Brasileirao B', 2024, 11, 'N987654321')
    into matches values ('Couto Pereira', date '2024-10-09', get_nipc('Mirassol'), get_nipc('Londrina'), 1, 0, 'Brasileirao B', 2024, 11, 'N123789456')
    into matches values ('Barradao', date '2024-10-09', get_nipc('Operario'), get_nipc('Ituano'), 1, 0, 'Brasileirao B', 2024, 11, 'N456123789')
    into matches values ('Arruda', date '2024-10-09', get_nipc('CRB'), get_nipc('Cuiaba'), 1, 1, 'Brasileirao B', 2024, 11, 'N456789123')
    
    --round 12
    into matches values ('Serrinha', date '2024-10-16', get_nipc('Brusque'), get_nipc('Coritiba'), 0, 2, 'Brasileirao B', 2024, 12, 'N123789456')
    into matches values ('Fonte Nova', date '2024-10-16', get_nipc('Mirassol'), get_nipc('America Mineiro'), 1, 0, 'Brasileirao B', 2024, 12, 'N456123789')
    into matches values ('Ilha do Retiro', date '2024-10-16', get_nipc('Operario'), get_nipc('Amazonas'), 2, 0, 'Brasileirao B', 2024, 12, 'N123456789')
    into matches values ('Arruda', date '2024-10-16', get_nipc('CRB'), get_nipc('Londrina'), 2, 0, 'Brasileirao B', 2024, 12, 'N456789123')
    into matches values ('Serra Dourada', date '2024-10-16', get_nipc('Cuiaba'), get_nipc('Ituano'), 2, 0, 'Brasileirao B', 2024, 12, 'N987654321')

    --round 13
    into matches values ('Estadio do Cafe', date '2024-11-24', get_nipc('CRB'), get_nipc('Coritiba'), 5, 0, 'Brasileirao B', 2024, 13, 'N123456789')
    into matches values ('Arena da Baixada', date '2024-11-24', get_nipc('Cuiaba'), get_nipc('Operario'), 1, 0, 'Brasileirao B', 2024, 13, 'N456789123')
    into matches values ('Couto Pereira', date '2024-11-24', get_nipc('Ituano'), get_nipc('Mirassol'), 2, 2, 'Brasileirao B', 2024, 13, 'N123789456')
    into matches values ('Barradao', date '2024-11-24', get_nipc('Londrina'), get_nipc('Brusque'), 2, 3, 'Brasileirao B', 2024, 13, 'N987654321')
    into matches values ('Aflitos', date '2024-11-24', get_nipc('Amazonas'), get_nipc('America Mineiro'), 0, 0, 'Brasileirao B', 2024, 13, 'N456123789')
    
    --round 14 
    into matches values ('Serrinha', date '2024-11-26', get_nipc('Londrina'), get_nipc('Coritiba'), 3, 3, 'Brasileirao B', 2024, 14, 'N123789456')
    into matches values ('Fonte Nova', date '2024-11-26', get_nipc('Amazonas'), get_nipc('Ituano'), 2, 1, 'Brasileirao B', 2024, 14, 'N456789123')
    into matches values ('Ilha do Retiro', date '2024-11-26', get_nipc('America Mineiro'), get_nipc('Cuiaba'), 1, 1, 'Brasileirao B', 2024, 14, 'N987654321')
    into matches values ('Arruda', date '2024-11-26', get_nipc('Brusque'), get_nipc('CRB'), 4, 2, 'Brasileirao B', 2024, 14, 'N123456789')
    into matches values ('Serra Dourada', date '2024-11-26', get_nipc('Mirassol'), get_nipc('Operario'), 1, 1, 'Brasileirao B', 2024, 14, 'N456123789')
    
    --round 15
    into matches values ('Estadio do Cafe', date '2024-12-07', get_nipc('Cuiaba'), get_nipc('Coritiba'), 2, 0, 'Brasileirao B', 2024, 15, 'N123456789')
    into matches values ('Arena da Baixada', date '2024-12-07', get_nipc('Ituano'), get_nipc('CRB'), 2, 0, 'Brasileirao B', 2024, 15, 'N987654321')
    into matches values ('Couto Pereira', date '2024-12-07', get_nipc('Londrina'), get_nipc('Operario'), 2, 0, 'Brasileirao B', 2024, 15, 'N123789456')
    into matches values ('Barradao', date '2024-12-07', get_nipc('Amazonas'), get_nipc('Mirassol'), 3, 0, 'Brasileirao B', 2024, 15, 'N456123789')
    into matches values ('Aflitos', date '2024-12-07', get_nipc('America Mineiro'), get_nipc('Brusque'), 4, 0, 'Brasileirao B', 2024, 15, 'N456789123')
    
    
    --round 16
    into matches values ('Serrinha', date '2024-12-15', get_nipc('Operario'), get_nipc('Coritiba'), 1, 1, 'Brasileirao B', 2024, 16, 'N123789456')
    into matches values ('Fonte Nova', date '2024-12-15', get_nipc('CRB'), get_nipc('Mirassol'), 3, 3, 'Brasileirao B', 2024, 16, 'N123456789')
    into matches values ('Ilha do Retiro', date '2024-12-15', get_nipc('Cuiaba'), get_nipc('Brusque'), 0, 0, 'Brasileirao B', 2024, 16, 'N987654321')
    into matches values ('Arruda', date '2024-12-15', get_nipc('Ituano'), get_nipc('America Mineiro'), 1, 0, 'Brasileirao B', 2024, 16, 'N456789123')
    into matches values ('Serra Dourada', date '2024-12-15', get_nipc('Londrina'), get_nipc('Amazonas'), 0, 0, 'Brasileirao B', 2024, 16, 'N456123789')
    
    
     --round 17
    into matches values ('Estadio do Cafe', date '2024-12-23', get_nipc('Ituano'), get_nipc('Coritiba'), 0, 0, 'Brasileirao B', 2024, 17, 'N123456789')
    into matches values ('Arena da Baixada', date '2024-12-23', get_nipc('Londrina'), get_nipc('Cuiaba'), 0, 0, 'Brasileirao B', 2024, 17, 'N456789123')
    into matches values ('Couto Pereira', date '2024-12-23', get_nipc('Amazonas'), get_nipc('CRB'), 2, 2, 'Brasileirao B', 2024, 17, 'N123789456')
    into matches values ('Barradao', date '2024-12-23', get_nipc('America Mineiro'), get_nipc('Operario'), 0, 1, 'Brasileirao B', 2024, 17, 'N987654321')
    into matches values ('Aflitos', date '2024-12-23', get_nipc('Brusque'), get_nipc('Mirassol'), 0, 0, 'Brasileirao B', 2024, 17, 'N456123789')
    
    
    
    --rodadas campeonato serie C 
    
       --round 1
    into matches values ('Heriberto Hulse', date '2022-05-17', get_nipc('Nautico'), get_nipc('Remo'), 2, 2, 'Brasileirao C', 2022, 1, 'N123456789')
    into matches values ('Arena Joinville', date '2022-05-17', get_nipc('Tuna Luso'), get_nipc('Nacional'), 0, 1, 'Brasileirao C', 2022, 1, 'N987654321')
    into matches values ('Durival Britto', date '2022-05-17', get_nipc('Sao Caetano'), get_nipc('Parana'), 1, 1, 'Brasileirao C', 2022, 1, 'N123789456')
    into matches values ('Barradao', date '2022-05-17', get_nipc('Santo Andre'), get_nipc('Criciuma'), 2, 2, 'Brasileirao C', 2022, 1, 'N456123789')
    into matches values ('Castelao', date '2022-05-17', get_nipc('Paysandu'), get_nipc('Joinville'), 0, 0, 'Brasileirao C', 2022, 1, 'N654321987')
    
     --round 2
    into matches values ('Moises Lucarelli', date '2022-05-24', get_nipc('Nautico'), get_nipc('Joinville'), 1, 1, 'Brasileirao C', 2022, 2, 'N987654321')
    into matches values ('Brinco de Ouro', date '2022-05-24', get_nipc('Criciuma'), get_nipc('Paysandu'), 2, 0, 'Brasileirao C', 2022, 2, 'N123456789')
    into matches values ('Anacleto Campanella', date '2022-05-24', get_nipc('Parana'), get_nipc('Santo Andre'), 1, 0, 'Brasileirao C', 2022, 2, 'N987321654')
    into matches values ('Bruno Jose Daniel', date '2022-05-24', get_nipc('Nacional'), get_nipc('Sao Caetano'), 3, 0, 'Brasileirao C', 2022, 2, 'N456123789')
    into matches values ('Alfredo Jaconi', date '2022-05-24', get_nipc('Remo'), get_nipc('Tuna Luso'), 0, 1, 'Brasileirao C', 2022, 2, 'N456789123')
    
     --round 3
    into matches values ('Heriberto Hulse', date '2022-06-07', get_nipc('Santo Andre'), get_nipc('Tuna Luso'), 5, 4, 'Brasileirao C', 2022, 3, 'N987654321')
    into matches values ('Moises Lucarelli', date '2022-06-07', get_nipc('Paysandu'), get_nipc('Remo'), 1, 1, 'Brasileirao C', 2022, 3, 'N123456789')
    into matches values ('Durival Britto', date '2022-06-07', get_nipc('Joinville'), get_nipc('Nacional'), 0, 0, 'Brasileirao C', 2022, 3, 'N123789456')
    into matches values ('Barradao', date '2022-06-07', get_nipc('Criciuma'), get_nipc('Parana'), 0, 2, 'Brasileirao C', 2022, 3, 'N456123789')
    into matches values ('Mangueirao', date '2022-06-07', get_nipc('Nautico'), get_nipc('Sao Caetano'), 1, 1, 'Brasileirao C', 2022, 3, 'N456789123')

    
     --round 4 
    into matches values ('Moises Lucarelli', date '2022-06-14', get_nipc('Nautico'), get_nipc('Santo Andre'), 0, 0, 'Brasileirao C', 2022, 4, 'N123456789')
    into matches values ('Brinco de Ouro', date '2022-06-14', get_nipc('Paysandu'), get_nipc('Sao Caetano'), 1, 2, 'Brasileirao C', 2022, 4, 'N987654321')
    into matches values ('Anacleto Campanella', date '2022-06-14', get_nipc('Joinville'), get_nipc('Tuna Luso'), 0, 0, 'Brasileirao C', 2022, 4, 'N123789456')
    into matches values ('Bruno Jose Daniel', date '2022-06-14', get_nipc('Criciuma'), get_nipc('Remo'), 1, 0, 'Brasileirao C', 2022, 4, 'N456123789')
    into matches values ('Alfredo Jaconi', date '2022-06-14', get_nipc('Parana'), get_nipc('Nacional'), 3, 0, 'Brasileirao C', 2022, 4, 'N456789123')
    
    --round 5
    into matches values ('Heriberto Hulse', date '2022-07-21', get_nipc('Nautico'), get_nipc('Paysandu'), 0, 0, 'Brasileirao C', 2022, 5, 'N123456789')
    into matches values ('Arena Joinville', date '2022-07-21', get_nipc('Joinville'), get_nipc('Santo Andre'), 2, 0, 'Brasileirao C', 2022, 5, 'N987654321')
    into matches values ('Durival Britto', date '2022-07-21', get_nipc('Criciuma'), get_nipc('Sao Caetano'), 1, 0, 'Brasileirao C', 2022, 5, 'N123789456')
    into matches values ('Barradao', date '2022-07-21', get_nipc('Parana'), get_nipc('Tuna Luso'), 1, 1, 'Brasileirao C', 2022, 5, 'N456123789')
    into matches values ('Moises Lucarelli', date '2022-07-21', get_nipc('Nacional'), get_nipc('Remo'), 0, 1, 'Brasileirao C', 2022, 5, 'N456789123')

    -- round 6
    into matches values ('Moises Lucarelli', date '2022-07-26', get_nipc('Nautico'), get_nipc('Criciuma'), 0, 0, 'Brasileirao C', 2022, 6, 'N123789456')
    into matches values ('Brinco de Ouro', date '2022-07-26', get_nipc('Parana'), get_nipc('Joinville'), 0, 0, 'Brasileirao C', 2022, 6, 'N456123789')
    into matches values ('Anacleto Campanella', date '2022-07-26', get_nipc('Nacional'), get_nipc('Paysandu'), 2, 2, 'Brasileirao C', 2022, 6, 'N123456789')
    into matches values ('Bruno Jose Daniel', date '2022-07-26', get_nipc('Remo'), get_nipc('Santo Andre'), 3, 3, 'Brasileirao C', 2022, 6, 'N456789123')
    into matches values ('Heriberto Hulse', date '2022-07-26', get_nipc('Tuna Luso'), get_nipc('Sao Caetano'), 1, 1, 'Brasileirao C', 2022, 6, 'N987654321')

     --round 7 
    into matches values ('Heriberto Hulse', date '2022-08-11', get_nipc('Nautico'), get_nipc('Parana'), 0, 2, 'Brasileirao C', 2022, 7, 'N123456789')
    into matches values ('Arena Joinville', date '2022-08-11', get_nipc('Nacional'), get_nipc('Criciuma'), 2, 2, 'Brasileirao C', 2022, 7, 'N456789123')
    into matches values ('Durival Britto', date '2022-08-11', get_nipc('Remo'), get_nipc('Joinville'), 0, 0, 'Brasileirao C', 2022, 7, 'N987654321')
    into matches values ('Sao Januario', date '2022-08-11', get_nipc('Tuna Luso'), get_nipc('Paysandu'), 1, 0, 'Brasileirao C', 2022, 7, 'N123789456')
    into matches values ('Mangueirao', date '2022-08-11', get_nipc('Sao Caetano'), get_nipc('Santo Andre'), 0, 3, 'Brasileirao C', 2022, 7, 'N456123789')
    
    --round 8
    into matches values ('Moises Lucarelli', date '2022-08-16', get_nipc('Nautico'), get_nipc('Nacional'), 0, 0, 'Brasileirao C', 2022, 8, 'N123456789')
    into matches values ('Brinco de Ouro', date '2022-08-16', get_nipc('Remo'), get_nipc('Parana'), 0, 1, 'Brasileirao C', 2022, 8, 'N987654321')
    into matches values ('Anacleto Campanella', date '2022-08-16', get_nipc('Tuna Luso'), get_nipc('Criciuma'), 2, 2, 'Brasileirao C', 2022, 8, 'N123789456')
    into matches values ('Bruno Jose Daniel', date '2022-08-16', get_nipc('Sao Caetano'), get_nipc('Joinville'), 2, 2, 'Brasileirao C', 2022, 8, 'N456123789')
    into matches values ('Alfredo Jaconi', date '2022-08-16', get_nipc('Santo Andre'), get_nipc('Paysandu'), 1, 0, 'Brasileirao C', 2022, 8, 'N654321987')
    
    --round 9
    into matches values ('Heriberto Hulse', date '2022-09-23', get_nipc('Nautico'), get_nipc('Tuna Luso'), 0, 0, 'Brasileirao C', 2022, 9, 'N123456789')
    into matches values ('Arena Joinville', date '2022-09-23', get_nipc('Sao Caetano'), get_nipc('Remo'), 2, 0, 'Brasileirao C', 2022, 9, 'N456789123')
    into matches values ('Durival Britto', date '2022-09-23', get_nipc('Santo Andre'), get_nipc('Nacional'), 0, 0, 'Brasileirao C', 2022, 9, 'N123789456')
    into matches values ('Sao Januario', date '2022-09-23', get_nipc('Paysandu'), get_nipc('Parana'), 2, 2, 'Brasileirao C', 2022, 9, 'N987654321')
    into matches values ('Bruno Jose Daniel', date '2022-09-23', get_nipc('Joinville'), get_nipc('Criciuma'), 1, 0, 'Brasileirao C', 2022, 9, 'N456123789')
    
    
    --round 10
    into matches values ('Moises Lucarelli', date '2022-10-02', get_nipc('Sao Caetano'), get_nipc('Nautico'), 3, 0, 'Brasileirao C', 2022, 10, 'N123789456')
    into matches values ('Brinco de Ouro', date '2022-10-02', get_nipc('Tuna Luso'), get_nipc('Santo Andre'), 2, 0, 'Brasileirao C', 2022, 10, 'N987321654')
    into matches values ('Anacleto Campanella', date '2022-10-02', get_nipc('Remo'), get_nipc('Paysandu'), 1, 0, 'Brasileirao C', 2022, 10, 'N987654321')
    into matches values ( 'Bruno Jose Daniel', date '2022-10-02', get_nipc('Nacional'), get_nipc('Joinville'), 0, 2, 'Brasileirao C', 2022, 10, 'N123456789')
    into matches values ('Alfredo Jaconi', date '2022-10-02', get_nipc('Parana'), get_nipc('Criciuma'), 0, 2, 'Brasileirao C', 2022, 10, 'N456789123')
    
    --round 11
    into matches values ('Heriberto Hulse', date '2022-10-07', get_nipc('Paysandu'), get_nipc('Nautico'), 1, 0, 'Brasileirao C', 2022, 11, 'N123456789')
    into matches values ('Fonte Nova', date '2022-10-07', get_nipc('Santo Andre'), get_nipc('Joinville'), 0, 2, 'Brasileirao C', 2022, 11, 'N987654321')
    into matches values ('Durival Britto', date '2022-10-07', get_nipc('Sao Caetano'), get_nipc('Criciuma'), 1, 0, 'Brasileirao C', 2022, 11, 'N123789456')
    into matches values ('Barradao', date '2022-10-07', get_nipc('Tuna Luso'), get_nipc('Parana'), 1, 0, 'Brasileirao C', 2022, 11, 'N456123789')
    into matches values ('Bruno Jose Daniel', date '2022-10-07', get_nipc('Remo'), get_nipc('Nacional'), 1, 1, 'Brasileirao C', 2022, 11, 'N456789123')
    
    --round 12
    into matches values ('Moises Lucarelli', date '2022-10-14', get_nipc('Santo Andre'), get_nipc('Nautico'), 0, 2, 'Brasileirao C', 2022, 12, 'N123789456')
    into matches values ('Brinco de Ouro', date '2022-10-14', get_nipc('Sao Caetano'), get_nipc('Paysandu'), 1, 0, 'Brasileirao C', 2022, 12, 'N456123789')
    into matches values ('Anacleto Campanella', date '2022-10-14', get_nipc('Tuna Luso'), get_nipc('Joinville'), 2, 0, 'Brasileirao C', 2022, 12, 'N123456789')
    into matches values ('Bruno Jose Daniel', date '2022-10-14', get_nipc('Remo'), get_nipc('Criciuma'), 2, 0, 'Brasileirao C', 2022, 12, 'N456789123')
    into matches values ('Alfredo Jaconi', date '2022-10-14', get_nipc('Nacional'), get_nipc('Parana'), 0, 1, 'Brasileirao C', 2022, 12, 'N987654321')

    --round 13
    into matches values ('Heriberto Hulse', date '2022-11-21', get_nipc('Remo'), get_nipc('Nautico'), 5, 0, 'Brasileirao C', 2022, 13, 'N123456789')
    into matches values ('Arena Joinville', date '2022-11-21', get_nipc('Nacional'), get_nipc('Tuna Luso'), 1, 0, 'Brasileirao C', 2022, 13, 'N456789123')
    into matches values ('Durival Britto', date '2022-11-21', get_nipc('Parana'), get_nipc('Sao Caetano'), 2, 2, 'Brasileirao C', 2022, 13, 'N123789456')
    into matches values ('Barradao', date '2022-11-21', get_nipc('Criciuma'), get_nipc('Santo Andre'), 2, 3, 'Brasileirao C', 2022, 13, 'N987654321')
    into matches values ('Mangueirao', date '2022-11-21', get_nipc('Joinville'), get_nipc('Paysandu'), 0, 0, 'Brasileirao C', 2022, 13, 'N456123789')
    
    --round 14 
    into matches values ('Moises Lucarelli', date '2022-11-28', get_nipc('Criciuma'), get_nipc('Nautico'), 3, 3, 'Brasileirao C', 2022, 14, 'N123789456')
    into matches values ('Brinco de Ouro', date '2022-11-28', get_nipc('Joinville'), get_nipc('Parana'), 2, 1, 'Brasileirao C', 2022, 14, 'N456789123')
    into matches values ('Anacleto Campanella', date '2022-11-28', get_nipc('Paysandu'), get_nipc('Nacional'), 1, 1, 'Brasileirao C', 2022, 14, 'N987654321')
    into matches values ('Bruno Jose Daniel', date '2022-11-28', get_nipc('Santo Andre'), get_nipc('Remo'), 4, 2, 'Brasileirao C', 2022, 14, 'N123456789')
    into matches values ('Alfredo Jaconi', date '2022-11-28', get_nipc('Sao Caetano'), get_nipc('Tuna Luso'), 1, 1, 'Brasileirao C', 2022, 14, 'N456123789')
    
    --round 15
    into matches values ('Heriberto Hulse', date '2022-12-05', get_nipc('Nacional'), get_nipc('Nautico'), 2, 0, 'Brasileirao C', 2022, 15, 'N123456789')
    into matches values ('Arena Joinville', date '2022-12-05', get_nipc('Parana'), get_nipc('Remo'), 2, 0, 'Brasileirao C', 2022, 15, 'N987654321')
    into matches values ('Durival Britto', date '2022-12-05', get_nipc('Criciuma'), get_nipc('Tuna Luso'), 2, 0, 'Brasileirao C', 2022, 15, 'N123789456')
    into matches values ('Barradao', date '2022-12-05', get_nipc('Joinville'), get_nipc('Sao Caetano'), 3, 0, 'Brasileirao C', 2022, 15, 'N456123789')
    into matches values ('Mangueirao', date '2022-12-05', get_nipc('Paysandu'), get_nipc('Santo Andre'), 4, 0, 'Brasileirao C', 2022, 15, 'N456789123')
    
    
    --round 16
    into matches values ('Moises Lucarelli', date '2022-12-12', get_nipc('Tuna Luso'), get_nipc('Nautico'), 1, 1, 'Brasileirao C', 2022, 16, 'N123789456')
    into matches values ('Brinco de Ouro', date '2022-12-12', get_nipc('Remo'), get_nipc('Sao Caetano'), 3, 3, 'Brasileirao C', 2022, 16, 'N123456789')
    into matches values ('Anacleto Campanella', date '2022-12-12', get_nipc('Nacional'), get_nipc('Santo Andre'), 0, 0, 'Brasileirao C', 2022, 16, 'N987654321')
    into matches values ('Bruno Jose Daniel', date '2022-12-12', get_nipc('Parana'), get_nipc('Paysandu'), 1, 1, 'Brasileirao C', 2022, 16, 'N456789123')
    into matches values ('Alfredo Jaconi', date '2022-12-12', get_nipc('Criciuma'), get_nipc('Joinville'), 0, 0, 'Brasileirao C', 2022, 16, 'N456123789')
    
    
     --round 17
    into matches values ('Heriberto Hulse', date '2022-12-21', get_nipc('Parana'), get_nipc('Nautico'), 0, 0, 'Brasileirao C', 2022, 17, 'N123456789')
    into matches values ('Arena Joinville', date '2022-12-21', get_nipc('Criciuma'), get_nipc('Nacional'), 0, 0, 'Brasileirao C', 2022, 17, 'N456789123')
    into matches values ('Durival Britto', date '2022-12-21', get_nipc('Joinville'), get_nipc('Remo'), 2, 2, 'Brasileirao C', 2022, 17, 'N123789456')
    into matches values ('Barradao', date '2022-12-21', get_nipc('Paysandu'), get_nipc('Tuna Luso'), 0, 1, 'Brasileirao C', 2022, 17, 'N987654321')
    into matches values ('Mangueirao', date '2022-12-21', get_nipc('Santo Andre'), get_nipc('Sao Caetano'), 0, 0, 'Brasileirao C', 2022, 17, 'N456123789')
    
    --campeonato serie C 2023 
    
        --round 1
    into matches values ('Heriberto Hulse', date '2023-05-17', get_nipc('Guarani'), get_nipc('Remo'), 2, 0, 'Brasileirao C', 2023, 1, 'N123456789')
    into matches values ('Arena Joinville', date '2023-05-17', get_nipc('Tuna Luso'), get_nipc('Nacional'), 0, 1, 'Brasileirao C', 2023, 1, 'N987654321')
    into matches values ('Durival Britto', date '2023-05-17', get_nipc('Sao Caetano'), get_nipc('Parana'), 1, 1, 'Brasileirao C', 2023, 1, 'N123789456')
    into matches values ('Barradao', date '2023-05-17', get_nipc('Santo Andre'), get_nipc('Criciuma'), 1, 2, 'Brasileirao C', 2023, 1, 'N456123789')
    into matches values ('Arena do Gremio', date '2023-05-17', get_nipc('Paysandu'), get_nipc('Joinville'), 0, 0, 'Brasileirao C', 2023, 1, 'N654321987')
    
     --round 2
    into matches values ('Moises Lucarelli', date '2023-05-24', get_nipc('Guarani'), get_nipc('Joinville'), 1, 1, 'Brasileirao C', 2023, 2, 'N987654321')
    into matches values ('Brinco de Ouro', date '2023-05-24', get_nipc('Criciuma'), get_nipc('Paysandu'), 2, 0, 'Brasileirao C', 2023, 2, 'N123456789')
    into matches values ('Anacleto Campanella', date '2023-05-24', get_nipc('Parana'), get_nipc('Santo Andre'), 1, 0, 'Brasileirao C', 2023, 2, 'N987321654')
    into matches values ('Bruno Jose Daniel', date '2023-05-24', get_nipc('Nacional'), get_nipc('Sao Caetano'), 3, 0, 'Brasileirao C', 2023, 2, 'N456123789')
    into matches values ('Alfredo Jaconi', date '2023-05-24', get_nipc('Remo'), get_nipc('Tuna Luso'), 0, 1, 'Brasileirao C', 2023, 2, 'N456789123')
    
     --round 3
    into matches values ('Heriberto Hulse', date '2023-06-07', get_nipc('Santo Andre'), get_nipc('Tuna Luso'), 5, 4, 'Brasileirao C', 2023, 3, 'N987654321')
    into matches values ('Moises Lucarelli', date '2023-06-07', get_nipc('Paysandu'), get_nipc('Remo'), 1, 1, 'Brasileirao C', 2023, 3, 'N123456789')
    into matches values ('Durival Britto', date '2023-06-07', get_nipc('Joinville'), get_nipc('Nacional'), 0, 0, 'Brasileirao C', 2023, 3, 'N123789456')
    into matches values ('Barradao', date '2023-06-07', get_nipc('Criciuma'), get_nipc('Parana'), 0, 2, 'Brasileirao C', 2023, 3, 'N456123789')
    into matches values ('Mangueirao', date '2023-06-07', get_nipc('Guarani'), get_nipc('Sao Caetano'), 1, 1, 'Brasileirao C', 2023, 3, 'N456789123')

    
     --round 4 
    into matches values ('Moises Lucarelli', date '2023-06-14', get_nipc('Guarani'), get_nipc('Santo Andre'), 0, 0, 'Brasileirao C', 2023, 4, 'N123456789')
    into matches values ('Brinco de Ouro', date '2023-06-14', get_nipc('Paysandu'), get_nipc('Sao Caetano'), 1, 2, 'Brasileirao C', 2023, 4, 'N987654321')
    into matches values ('Anacleto Campanella', date '2023-06-14', get_nipc('Joinville'), get_nipc('Tuna Luso'), 0, 0, 'Brasileirao C', 2023, 4, 'N123789456')
    into matches values ('Bruno Jose Daniel', date '2023-06-14', get_nipc('Criciuma'), get_nipc('Remo'), 1, 0, 'Brasileirao C', 2023, 4, 'N456123789')
    into matches values ('Alfredo Jaconi', date '2023-06-14', get_nipc('Parana'), get_nipc('Nacional'), 3, 0, 'Brasileirao C', 2023, 4, 'N456789123')
    
    --round 5
    into matches values ('Heriberto Hulse', date '2023-07-21', get_nipc('Guarani'), get_nipc('Paysandu'), 0, 0, 'Brasileirao C', 2023, 5, 'N123456789')
    into matches values ('Arena Joinville', date '2023-07-21', get_nipc('Joinville'), get_nipc('Santo Andre'), 2, 0, 'Brasileirao C', 2023, 5, 'N987654321')
    into matches values ('Durival Britto', date '2023-07-21', get_nipc('Criciuma'), get_nipc('Sao Caetano'), 1, 0, 'Brasileirao C', 2023, 5, 'N123789456')
    into matches values ('Barradao', date '2023-07-21', get_nipc('Parana'), get_nipc('Tuna Luso'), 1, 1, 'Brasileirao C', 2023, 5, 'N456123789')
    into matches values ('Moises Lucarelli', date '2023-07-21', get_nipc('Nacional'), get_nipc('Remo'), 0, 1, 'Brasileirao C', 2023, 5, 'N456789123')

    -- round 6
    into matches values ('Moises Lucarelli', date '2023-07-26', get_nipc('Guarani'), get_nipc('Criciuma'), 0, 0, 'Brasileirao C', 2023, 6, 'N123789456')
    into matches values ('Brinco de Ouro', date '2023-07-26', get_nipc('Parana'), get_nipc('Joinville'), 0, 0, 'Brasileirao C', 2023, 6, 'N456123789')
    into matches values ('Anacleto Campanella', date '2023-07-26', get_nipc('Nacional'), get_nipc('Paysandu'), 2, 2, 'Brasileirao C', 2023, 6, 'N123456789')
    into matches values ('Bruno Jose Daniel', date '2023-07-26', get_nipc('Remo'), get_nipc('Santo Andre'), 3, 3, 'Brasileirao C', 2023, 6, 'N456789123')
    into matches values ('Heriberto Hulse', date '2023-07-26', get_nipc('Tuna Luso'), get_nipc('Sao Caetano'), 1, 1, 'Brasileirao C', 2023, 6, 'N987654321')
    
     --round 7 
    into matches values ('Heriberto Hulse', date '2023-08-11', get_nipc('Guarani'), get_nipc('Parana'), 0, 2, 'Brasileirao C', 2023, 7, 'N123456789')
    into matches values ('Arena Joinville', date '2023-08-11', get_nipc('Nacional'), get_nipc('Criciuma'), 2, 2, 'Brasileirao C', 2023, 7, 'N456789123')
    into matches values ('Durival Britto', date '2023-08-11', get_nipc('Remo'), get_nipc('Joinville'), 0, 0, 'Brasileirao C', 2023, 7, 'N987654321')
    into matches values ('Sao Januario', date '2023-08-11', get_nipc('Tuna Luso'), get_nipc('Paysandu'), 1, 0, 'Brasileirao C', 2023, 7, 'N123789456')
    into matches values ('Mangueirao', date '2023-08-11', get_nipc('Sao Caetano'), get_nipc('Santo Andre'), 0, 3, 'Brasileirao C', 2023, 7, 'N456123789')
    
    --round 8
    into matches values ('Moises Lucarelli', date '2023-08-16', get_nipc('Guarani'), get_nipc('Nacional'), 0, 0, 'Brasileirao C', 2023, 8, 'N123456789')
    into matches values ('Brinco de Ouro', date '2023-08-16', get_nipc('Remo'), get_nipc('Parana'), 0, 1, 'Brasileirao C', 2023, 8, 'N987654321')
    into matches values ('Anacleto Campanella', date '2023-08-16', get_nipc('Tuna Luso'), get_nipc('Criciuma'), 2, 2, 'Brasileirao C', 2023, 8, 'N123789456')
    into matches values ('Bruno Jose Daniel', date '2023-08-16', get_nipc('Sao Caetano'), get_nipc('Joinville'), 2, 2, 'Brasileirao C', 2023, 8, 'N456123789')
    into matches values ('Alfredo Jaconi', date '2023-08-16', get_nipc('Santo Andre'), get_nipc('Paysandu'), 1, 0, 'Brasileirao C', 2023, 8, 'N654321987')
    
    --round 9
    into matches values ('Heriberto Hulse', date '2023-09-23', get_nipc('Guarani'), get_nipc('Tuna Luso'), 0, 0, 'Brasileirao C', 2023, 9, 'N123456789')
    into matches values ('Arena Joinville', date '2023-09-23', get_nipc('Sao Caetano'), get_nipc('Remo'), 2, 0, 'Brasileirao C', 2023, 9, 'N456789123')
    into matches values ('Durival Britto', date '2023-09-23', get_nipc('Santo Andre'), get_nipc('Nacional'), 0, 0, 'Brasileirao C', 2023, 9, 'N123789456')
    into matches values ('Sao Januario', date '2023-09-23', get_nipc('Paysandu'), get_nipc('Parana'), 2, 2, 'Brasileirao C', 2023, 9, 'N987654321')
    into matches values ('Bruno Jose Daniel', date '2023-09-23', get_nipc('Joinville'), get_nipc('Criciuma'), 1, 0, 'Brasileirao C', 2023, 9, 'N456123789')
    
    
    --round 10
    into matches values ('Moises Lucarelli', date '2023-10-02', get_nipc('Sao Caetano'), get_nipc('Guarani'), 3, 0, 'Brasileirao C', 2023, 10, 'N123789456')
    into matches values ('Brinco de Ouro', date '2023-10-02', get_nipc('Tuna Luso'), get_nipc('Santo Andre'), 2, 0, 'Brasileirao C', 2023, 10, 'N987321654')
    into matches values ('Anacleto Campanella', date '2023-10-02', get_nipc('Remo'), get_nipc('Paysandu'), 1, 0, 'Brasileirao C', 2023, 10, 'N987654321')
    into matches values ( 'Bruno Jose Daniel', date '2023-10-02', get_nipc('Nacional'), get_nipc('Joinville'), 0, 2, 'Brasileirao C', 2023, 10, 'N123456789')
    into matches values ('Alfredo Jaconi', date '2023-10-02', get_nipc('Parana'), get_nipc('Criciuma'), 0, 2, 'Brasileirao C', 2023, 10, 'N456789123')
    
    
    --round 11
    into matches values ('Heriberto Hulse', date '2023-10-07', get_nipc('Paysandu'), get_nipc('Guarani'), 1, 0, 'Brasileirao C', 2023, 11, 'N123456789')
    into matches values ('Fonte Nova', date '2023-10-07', get_nipc('Santo Andre'), get_nipc('Joinville'), 0, 2, 'Brasileirao C', 2023, 11, 'N987654321')
    into matches values ('Durival Britto', date '2023-10-07', get_nipc('Sao Caetano'), get_nipc('Criciuma'), 1, 0, 'Brasileirao C', 2023, 11, 'N123789456')
    into matches values ('Barradao', date '2023-10-07', get_nipc('Tuna Luso'), get_nipc('Parana'), 1, 0, 'Brasileirao C', 2023, 11, 'N456123789')
    into matches values ('Bruno Jose Daniel', date '2023-10-07', get_nipc('Remo'), get_nipc('Nacional'), 1, 1, 'Brasileirao C', 2023, 11, 'N456789123')
    
    --round 12
    into matches values ('Moises Lucarelli', date '2023-10-14', get_nipc('Santo Andre'), get_nipc('Guarani'), 0, 2, 'Brasileirao C', 2023, 12, 'N123789456')
    into matches values ('Brinco de Ouro', date '2023-10-14', get_nipc('Sao Caetano'), get_nipc('Paysandu'), 1, 0, 'Brasileirao C', 2023, 12, 'N456123789')
    into matches values ('Anacleto Campanella', date '2023-10-14', get_nipc('Tuna Luso'), get_nipc('Joinville'), 2, 0, 'Brasileirao C', 2023, 12, 'N123456789')
    into matches values ('Bruno Jose Daniel', date '2023-10-14', get_nipc('Remo'), get_nipc('Criciuma'), 2, 0, 'Brasileirao C', 2023, 12, 'N456789123')
    into matches values ('Alfredo Jaconi', date '2023-10-14', get_nipc('Nacional'), get_nipc('Parana'), 2, 0, 'Brasileirao C', 2023, 12, 'N987654321')
    
    --round 13
    into matches values ('Heriberto Hulse', date '2023-11-21', get_nipc('Remo'), get_nipc('Guarani'), 5, 0, 'Brasileirao C', 2023, 13, 'N123456789')
    into matches values ('Arena Joinville', date '2023-11-21', get_nipc('Nacional'), get_nipc('Tuna Luso'), 1, 0, 'Brasileirao C', 2023, 13, 'N456789123')
    into matches values ('Durival Britto', date '2023-11-21', get_nipc('Parana'), get_nipc('Sao Caetano'), 2, 2, 'Brasileirao C', 2023, 13, 'N123789456')
    into matches values ('Barradao', date '2023-11-21', get_nipc('Criciuma'), get_nipc('Santo Andre'), 2, 3, 'Brasileirao C', 2023, 13, 'N987654321')
    into matches values ('Mangueirao', date '2023-11-21', get_nipc('Joinville'), get_nipc('Paysandu'), 0, 0, 'Brasileirao C', 2023, 13, 'N456123789')
    
    --round 14 
    into matches values ('Moises Lucarelli', date '2023-11-28', get_nipc('Criciuma'), get_nipc('Guarani'), 3, 3, 'Brasileirao C', 2023, 14, 'N123789456')
    into matches values ('Brinco de Ouro', date '2023-11-28', get_nipc('Joinville'), get_nipc('Parana'), 2, 1, 'Brasileirao C', 2023, 14, 'N456789123')
    into matches values ('Anacleto Campanella', date '2023-11-28', get_nipc('Paysandu'), get_nipc('Nacional'), 1, 1, 'Brasileirao C', 2023, 14, 'N987654321')
    into matches values ('Bruno Jose Daniel', date '2023-11-28', get_nipc('Santo Andre'), get_nipc('Remo'), 4, 2, 'Brasileirao C', 2023, 14, 'N123456789')
    into matches values ('Alfredo Jaconi', date '2023-11-28', get_nipc('Sao Caetano'), get_nipc('Tuna Luso'), 1, 1, 'Brasileirao C', 2023, 14, 'N456123789')
    
    --round 15
    into matches values ('Heriberto Hulse', date '2023-12-05', get_nipc('Nacional'), get_nipc('Guarani'), 2, 0, 'Brasileirao C', 2023, 15, 'N123456789')
    into matches values ('Arena Joinville', date '2023-12-05', get_nipc('Parana'), get_nipc('Remo'), 2, 0, 'Brasileirao C', 2023, 15, 'N987654321')
    into matches values ('Durival Britto', date '2023-12-05', get_nipc('Criciuma'), get_nipc('Tuna Luso'), 2, 0, 'Brasileirao C', 2023, 15, 'N123789456')
    into matches values ('Barradao', date '2023-12-05', get_nipc('Joinville'), get_nipc('Sao Caetano'), 3, 0, 'Brasileirao C', 2023, 15, 'N456123789')
    into matches values ('Mangueirao', date '2023-12-05', get_nipc('Paysandu'), get_nipc('Santo Andre'), 4, 0, 'Brasileirao C', 2023, 15, 'N456789123')
    
    
    --round 16
    into matches values ('Moises Lucarelli', date '2023-12-12', get_nipc('Tuna Luso'), get_nipc('Guarani'), 1, 1, 'Brasileirao C', 2023, 16, 'N123789456')
    into matches values ('Brinco de Ouro', date '2023-12-12', get_nipc('Remo'), get_nipc('Sao Caetano'), 3, 3, 'Brasileirao C', 2023, 16, 'N123456789')
    into matches values ('Anacleto Campanella', date '2023-12-12', get_nipc('Nacional'), get_nipc('Santo Andre'), 0, 0, 'Brasileirao C', 2023, 16, 'N987654321')
    into matches values ('Bruno Jose Daniel', date '2023-12-12', get_nipc('Parana'), get_nipc('Paysandu'), 1, 0, 'Brasileirao C', 2023, 16, 'N456789123')
    into matches values ('Alfredo Jaconi', date '2023-12-12', get_nipc('Criciuma'), get_nipc('Joinville'), 0, 0, 'Brasileirao C', 2023, 16, 'N456123789')
    
    
     --round 17
    into matches values ('Heriberto Hulse', date '2023-12-21', get_nipc('Parana'), get_nipc('Guarani'), 0, 0, 'Brasileirao C', 2023, 17, 'N123456789')
    into matches values ('Arena Joinville', date '2023-12-21', get_nipc('Criciuma'), get_nipc('Nacional'), 0, 0, 'Brasileirao C', 2023, 17, 'N456789123')
    into matches values ('Durival Britto', date '2023-12-21', get_nipc('Joinville'), get_nipc('Remo'), 2, 2, 'Brasileirao C', 2023, 17, 'N123789456')
    into matches values ('Barradao', date '2023-12-21', get_nipc('Paysandu'), get_nipc('Tuna Luso'), 0, 1, 'Brasileirao C', 2023, 17, 'N987654321')
    into matches values ('Mangueirao', date '2023-12-21', get_nipc('Santo Andre'), get_nipc('Sao Caetano'), 0, 0, 'Brasileirao C', 2023, 17, 'N456123789')
    
    --campeonato serie C 2022 
         --round 1
    into matches values ('Heriberto Hulse', date '2024-05-17', get_nipc('Avai'), get_nipc('Remo'), 2, 0, 'Brasileirao C', 2024, 1, 'N123456789')
    into matches values ('Arena Joinville', date '2024-05-17', get_nipc('Tuna Luso'), get_nipc('Nacional'), 0, 1, 'Brasileirao C', 2024, 1, 'N987654321')
    into matches values ('Durival Britto', date '2024-05-17', get_nipc('Sao Caetano'), get_nipc('Parana'), 1, 1, 'Brasileirao C', 2024, 1, 'N123789456')
    into matches values ('Barradao', date '2024-05-17', get_nipc('Santo Andre'), get_nipc('Criciuma'), 1, 2, 'Brasileirao C', 2024, 1, 'N456123789')
    into matches values ('Arena do Gremio', date '2024-05-17', get_nipc('Paysandu'), get_nipc('Joinville'), 0, 0, 'Brasileirao C', 2024, 1, 'N654321987')
    
     --round 2
    into matches values ('Moises Lucarelli', date '2024-05-24', get_nipc('Avai'), get_nipc('Joinville'), 1, 1, 'Brasileirao C', 2024, 2, 'N987654321')
    into matches values ('Brinco de Ouro', date '2024-05-24', get_nipc('Criciuma'), get_nipc('Paysandu'), 2, 0, 'Brasileirao C', 2024, 2, 'N123456789')
    into matches values ('Anacleto Campanella', date '2024-05-24', get_nipc('Parana'), get_nipc('Santo Andre'), 1, 0, 'Brasileirao C', 2024, 2, 'N987321654')
    into matches values ('Bruno Jose Daniel', date '2024-05-24', get_nipc('Nacional'), get_nipc('Sao Caetano'), 3, 0, 'Brasileirao C', 2024, 2, 'N456123789')
    into matches values ('Alfredo Jaconi', date '2024-05-24', get_nipc('Remo'), get_nipc('Tuna Luso'), 0, 1, 'Brasileirao C', 2024, 2, 'N456789123')
    
     --round 3
    into matches values ('Heriberto Hulse', date '2024-06-07', get_nipc('Santo Andre'), get_nipc('Tuna Luso'), 5, 4, 'Brasileirao C', 2024, 3, 'N987654321')
    into matches values ('Moises Lucarelli', date '2024-06-07', get_nipc('Paysandu'), get_nipc('Remo'), 1, 1, 'Brasileirao C', 2024, 3, 'N123456789')
    into matches values ('Durival Britto', date '2024-06-07', get_nipc('Joinville'), get_nipc('Nacional'), 0, 0, 'Brasileirao C', 2024, 3, 'N123789456')
    into matches values ('Barradao', date '2024-06-07', get_nipc('Criciuma'), get_nipc('Parana'), 0, 2, 'Brasileirao C', 2024, 3, 'N456123789')
    into matches values ('Mangueirao', date '2024-06-07', get_nipc('Avai'), get_nipc('Sao Caetano'), 1, 1, 'Brasileirao C', 2024, 3, 'N456789123')

    
     --round 4 
    into matches values ('Moises Lucarelli', date '2024-06-14', get_nipc('Avai'), get_nipc('Santo Andre'), 0, 0, 'Brasileirao C', 2024, 4, 'N123456789')
    into matches values ('Brinco de Ouro', date '2024-06-14', get_nipc('Paysandu'), get_nipc('Sao Caetano'), 1, 2, 'Brasileirao C', 2024, 4, 'N987654321')
    into matches values ('Anacleto Campanella', date '2024-06-14', get_nipc('Joinville'), get_nipc('Tuna Luso'), 0, 0, 'Brasileirao C', 2024, 4, 'N123789456')
    into matches values ('Bruno Jose Daniel', date '2024-06-14', get_nipc('Criciuma'), get_nipc('Remo'), 1, 0, 'Brasileirao C', 2024, 4, 'N456123789')
    into matches values ('Alfredo Jaconi', date '2024-06-14', get_nipc('Parana'), get_nipc('Nacional'), 3, 0, 'Brasileirao C', 2024, 4, 'N456789123')
    
    --round 5
    into matches values ('Heriberto Hulse', date '2024-07-21', get_nipc('Avai'), get_nipc('Paysandu'), 0, 0, 'Brasileirao C', 2024, 5, 'N123456789')
    into matches values ('Arena Joinville', date '2024-07-21', get_nipc('Joinville'), get_nipc('Santo Andre'), 2, 0, 'Brasileirao C', 2024, 5, 'N987654321')
    into matches values ('Durival Britto', date '2024-07-21', get_nipc('Criciuma'), get_nipc('Sao Caetano'), 1, 0, 'Brasileirao C', 2024, 5, 'N123789456')
    into matches values ('Barradao', date '2024-07-21', get_nipc('Parana'), get_nipc('Tuna Luso'), 1, 1, 'Brasileirao C', 2024, 5, 'N456123789')
    into matches values ('Moises Lucarelli', date '2024-07-21', get_nipc('Nacional'), get_nipc('Remo'), 0, 1, 'Brasileirao C', 2024, 5, 'N456789123')

    -- round 6
    into matches values ('Moises Lucarelli', date '2024-07-26', get_nipc('Avai'), get_nipc('Criciuma'), 0, 0, 'Brasileirao C', 2024, 6, 'N123789456')
    into matches values ('Brinco de Ouro', date '2024-07-26', get_nipc('Parana'), get_nipc('Joinville'), 0, 0, 'Brasileirao C', 2024, 6, 'N456123789')
    into matches values ('Anacleto Campanella', date '2024-07-26', get_nipc('Nacional'), get_nipc('Paysandu'), 2, 2, 'Brasileirao C', 2024, 6, 'N123456789')
    into matches values ('Bruno Jose Daniel', date '2024-07-26', get_nipc('Remo'), get_nipc('Santo Andre'), 3, 3, 'Brasileirao C', 2024, 6, 'N456789123')
    into matches values ('Heriberto Hulse', date '2024-07-26', get_nipc('Tuna Luso'), get_nipc('Sao Caetano'), 1, 1, 'Brasileirao C', 2024, 6, 'N987654321')
    
      --round 7 
    into matches values ('Heriberto Hulse', date '2024-08-11', get_nipc('Avai'), get_nipc('Parana'), 0, 2, 'Brasileirao C', 2024, 7, 'N123456789')
    into matches values ('Arena Joinville', date '2024-08-11', get_nipc('Nacional'), get_nipc('Criciuma'), 2, 2, 'Brasileirao C', 2024, 7, 'N456789123')
    into matches values ('Durival Britto', date '2024-08-11', get_nipc('Remo'), get_nipc('Joinville'), 0, 0, 'Brasileirao C', 2024, 7, 'N987654321')
    into matches values ('Sao Januario', date '2024-08-11', get_nipc('Tuna Luso'), get_nipc('Paysandu'), 1, 0, 'Brasileirao C', 2024, 7, 'N123789456')
    into matches values ('Mangueirao', date '2024-08-11', get_nipc('Sao Caetano'), get_nipc('Santo Andre'), 0, 3, 'Brasileirao C', 2024, 7, 'N456123789')
    
    --round 8
    into matches values ('Moises Lucarelli', date '2024-08-16', get_nipc('Avai'), get_nipc('Nacional'), 0, 0, 'Brasileirao C', 2024, 8, 'N123456789')
    into matches values ('Brinco de Ouro', date '2024-08-16', get_nipc('Remo'), get_nipc('Parana'), 0, 1, 'Brasileirao C', 2024, 8, 'N987654321')
    into matches values ('Anacleto Campanella', date '2024-08-16', get_nipc('Tuna Luso'), get_nipc('Criciuma'), 2, 2, 'Brasileirao C', 2024, 8, 'N123789456')
    into matches values ('Bruno Jose Daniel', date '2024-08-16', get_nipc('Sao Caetano'), get_nipc('Joinville'), 2, 2, 'Brasileirao C', 2024, 8, 'N456123789')
    into matches values ('Alfredo Jaconi', date '2024-08-16', get_nipc('Santo Andre'), get_nipc('Paysandu'), 1, 0, 'Brasileirao C', 2024, 8, 'N654321987')
    
    --round 9
    into matches values ('Heriberto Hulse', date '2024-09-23', get_nipc('Avai'), get_nipc('Tuna Luso'), 0, 0, 'Brasileirao C', 2024, 9, 'N123456789')
    into matches values ('Arena Joinville', date '2024-09-23', get_nipc('Sao Caetano'), get_nipc('Remo'), 2, 0, 'Brasileirao C', 2024, 9, 'N456789123')
    into matches values ('Durival Britto', date '2024-09-23', get_nipc('Santo Andre'), get_nipc('Nacional'), 0, 0, 'Brasileirao C', 2024, 9, 'N123789456')
    into matches values ('Sao Januario', date '2024-09-23', get_nipc('Paysandu'), get_nipc('Parana'), 2, 2, 'Brasileirao C', 2024, 9, 'N987654321')
    into matches values ('Bruno Jose Daniel', date '2024-09-23', get_nipc('Joinville'), get_nipc('Criciuma'), 1, 0, 'Brasileirao C', 2024, 9, 'N456123789')
    
    
    --round 10
    into matches values ('Moises Lucarelli', date '2024-10-02', get_nipc('Sao Caetano'), get_nipc('Avai'), 3, 0, 'Brasileirao C', 2024, 10, 'N123789456')
    into matches values ('Brinco de Ouro', date '2024-10-02', get_nipc('Tuna Luso'), get_nipc('Santo Andre'), 2, 0, 'Brasileirao C', 2024, 10, 'N987321654')
    into matches values ('Anacleto Campanella', date '2024-10-02', get_nipc('Remo'), get_nipc('Paysandu'), 1, 0, 'Brasileirao C', 2024, 10, 'N987654321')
    into matches values ( 'Bruno Jose Daniel', date '2024-10-02', get_nipc('Nacional'), get_nipc('Joinville'), 0, 2, 'Brasileirao C', 2024, 10, 'N123456789')
    into matches values ('Alfredo Jaconi', date '2024-10-02', get_nipc('Parana'), get_nipc('Criciuma'), 0, 2, 'Brasileirao C', 2024, 10, 'N456789123')
    
    
    --round 11
    into matches values ('Heriberto Hulse', date '2024-10-07', get_nipc('Paysandu'), get_nipc('Avai'), 1, 0, 'Brasileirao C', 2024, 11, 'N123456789')
    into matches values ('Fonte Nova', date '2024-10-07', get_nipc('Santo Andre'), get_nipc('Joinville'), 0, 2, 'Brasileirao C', 2024, 11, 'N987654321')
    into matches values ('Durival Britto', date '2024-10-07', get_nipc('Sao Caetano'), get_nipc('Criciuma'), 1, 0, 'Brasileirao C', 2024, 11, 'N123789456')
    into matches values ('Barradao', date '2024-10-07', get_nipc('Tuna Luso'), get_nipc('Parana'), 1, 0, 'Brasileirao C', 2024, 11, 'N456123789')
    into matches values ('Bruno Jose Daniel', date '2024-10-07', get_nipc('Remo'), get_nipc('Nacional'), 1, 1, 'Brasileirao C', 2024, 11, 'N456789123')
    
    --round 12
    into matches values ('Moises Lucarelli', date '2024-10-14', get_nipc('Santo Andre'), get_nipc('Avai'), 0, 2, 'Brasileirao C', 2024, 12, 'N123789456')
    into matches values ('Brinco de Ouro', date '2024-10-14', get_nipc('Sao Caetano'), get_nipc('Paysandu'), 1, 0, 'Brasileirao C', 2024, 12, 'N456123789')
    into matches values ('Anacleto Campanella', date '2024-10-14', get_nipc('Tuna Luso'), get_nipc('Joinville'), 2, 0, 'Brasileirao C', 2024, 12, 'N123456789')
    into matches values ('Bruno Jose Daniel', date '2024-10-14', get_nipc('Remo'), get_nipc('Criciuma'), 2, 0, 'Brasileirao C', 2024, 12, 'N456789123')
    into matches values ('Alfredo Jaconi', date '2024-10-14', get_nipc('Nacional'), get_nipc('Parana'), 2, 0, 'Brasileirao C', 2024, 12, 'N987654321')
    
    --round 13
    into matches values ('Heriberto Hulse', date '2024-11-21', get_nipc('Remo'), get_nipc('Avai'), 5, 0, 'Brasileirao C', 2024, 13, 'N123456789')
    into matches values ('Arena Joinville', date '2024-11-21', get_nipc('Nacional'), get_nipc('Tuna Luso'), 1, 0, 'Brasileirao C', 2024, 13, 'N456789123')
    into matches values ('Durival Britto', date '2024-11-21', get_nipc('Parana'), get_nipc('Sao Caetano'), 2, 2, 'Brasileirao C', 2024, 13, 'N123789456')
    into matches values ('Barradao', date '2024-11-21', get_nipc('Criciuma'), get_nipc('Santo Andre'), 2, 3, 'Brasileirao C', 2024, 13, 'N987654321')
    into matches values ('Mangueirao', date '2024-11-21', get_nipc('Joinville'), get_nipc('Paysandu'), 0, 0, 'Brasileirao C', 2024, 13, 'N456123789')
    
    --round 14 
    into matches values ('Moises Lucarelli', date '2024-11-28', get_nipc('Criciuma'), get_nipc('Avai'), 3, 3, 'Brasileirao C', 2024, 14, 'N123789456')
    into matches values ('Brinco de Ouro', date '2024-11-28', get_nipc('Joinville'), get_nipc('Parana'), 2, 1, 'Brasileirao C', 2024, 14, 'N456789123')
    into matches values ('Anacleto Campanella', date '2024-11-28', get_nipc('Paysandu'), get_nipc('Nacional'), 1, 1, 'Brasileirao C', 2024, 14, 'N987654321')
    into matches values ('Bruno Jose Daniel', date '2024-11-28', get_nipc('Santo Andre'), get_nipc('Remo'), 4, 2, 'Brasileirao C', 2024, 14, 'N123456789')
    into matches values ('Alfredo Jaconi', date '2024-11-28', get_nipc('Sao Caetano'), get_nipc('Tuna Luso'), 1, 1, 'Brasileirao C', 2024, 14, 'N456123789')
    
    --round 15
    into matches values ('Heriberto Hulse', date '2024-12-05', get_nipc('Nacional'), get_nipc('Avai'), 2, 0, 'Brasileirao C', 2024, 15, 'N123456789')
    into matches values ('Arena Joinville', date '2024-12-05', get_nipc('Parana'), get_nipc('Remo'), 2, 0, 'Brasileirao C', 2024, 15, 'N987654321')
    into matches values ('Durival Britto', date '2024-12-05', get_nipc('Criciuma'), get_nipc('Tuna Luso'), 2, 0, 'Brasileirao C', 2024, 15, 'N123789456')
    into matches values ('Barradao', date '2024-12-05', get_nipc('Joinville'), get_nipc('Sao Caetano'), 3, 0, 'Brasileirao C', 2024, 15, 'N456123789')
    into matches values ('Mangueirao', date '2024-12-05', get_nipc('Paysandu'), get_nipc('Santo Andre'), 4, 0, 'Brasileirao C', 2024, 15, 'N456789123')
    
    
    --round 16
    into matches values ('Moises Lucarelli', date '2024-12-12', get_nipc('Tuna Luso'), get_nipc('Avai'), 1, 1, 'Brasileirao C', 2024, 16, 'N123789456')
    into matches values ('Brinco de Ouro', date '2024-12-12', get_nipc('Remo'), get_nipc('Sao Caetano'), 3, 3, 'Brasileirao C', 2024, 16, 'N123456789')
    into matches values ('Anacleto Campanella', date '2024-12-12', get_nipc('Nacional'), get_nipc('Santo Andre'), 0, 0, 'Brasileirao C', 2024, 16, 'N987654321')
    into matches values ('Bruno Jose Daniel', date '2024-12-12', get_nipc('Parana'), get_nipc('Paysandu'), 1, 0, 'Brasileirao C', 2024, 16, 'N456789123')
    into matches values ('Alfredo Jaconi', date '2024-12-12', get_nipc('Criciuma'), get_nipc('Joinville'), 0, 0, 'Brasileirao C', 2024, 16, 'N456123789')
    
    
     --round 17
    into matches values ('Heriberto Hulse', date '2024-12-21', get_nipc('Parana'), get_nipc('Avai'), 0, 0, 'Brasileirao C', 2024, 17, 'N123456789')
    into matches values ('Arena Joinville', date '2024-12-21', get_nipc('Criciuma'), get_nipc('Nacional'), 0, 0, 'Brasileirao C', 2024, 17, 'N456789123')
    into matches values ('Durival Britto', date '2024-12-21', get_nipc('Joinville'), get_nipc('Remo'), 2, 2, 'Brasileirao C', 2024, 17, 'N123789456')
    into matches values ('Barradao', date '2024-12-21', get_nipc('Paysandu'), get_nipc('Tuna Luso'), 0, 1, 'Brasileirao C', 2024, 17, 'N987654321')
    into matches values ('Mangueirao', date '2024-12-21', get_nipc('Santo Andre'), get_nipc('Sao Caetano'), 0, 0, 'Brasileirao C', 2024, 17, 'N456123789')
select * from dual;


call issue_tickets('Maracana', date '2024-05-18', 1000, 50);
call issue_tickets('Vila Belmiro', date '2024-05-18', 1000, 50);
call issue_tickets('Morumbi', date '2024-05-18', 1000, 50);
call issue_tickets('Sao Januario', date '2024-05-18', 1000, 50);
call issue_tickets('Arena do Gremio', date '2024-05-18', 1000, 50);


call issue_tickets('Beira-Rio', date '2024-05-25', 1000, 50);
call issue_tickets('Allianz Parque', date '2024-05-25', 1000, 50);
call issue_tickets('Arena Corinthians', date '2024-05-25', 1000, 50);
call issue_tickets('Nilton Santos', date '2024-05-25', 1000, 50);
call issue_tickets('Mineirao', date '2024-05-25', 1000, 50);

call issue_tickets('Maracana', date '2024-06-08', 1000, 50);
call issue_tickets('Beira-Rio', date '2024-06-08', 1000, 50);
call issue_tickets('Morumbi', date '2024-06-08', 1000, 50);
call issue_tickets('Sao Januario', date '2024-06-08', 1000, 50);
call issue_tickets('Arena do Gremio', date '2024-06-08', 1000, 50);

call issue_tickets('Beira-Rio', date '2024-06-15', 1000, 50);
call issue_tickets('Allianz Parque', date '2024-06-15', 1000, 50);
call issue_tickets('Arena Corinthians', date '2024-06-15', 1000, 50);
call issue_tickets('Nilton Santos', date '2024-06-15', 1000, 50);
call issue_tickets('Mineirao', date '2024-06-15', 1000, 50);

call issue_tickets('Maracana', date '2024-07-20', 1000, 50);
call issue_tickets('Vila Belmiro', date '2024-07-20', 1000, 50);
call issue_tickets('Morumbi', date '2024-07-20', 1000, 50);
call issue_tickets('Sao Januario', date '2024-07-20', 1000, 50);
call issue_tickets('Beira-Rio', date '2024-07-20', 1000, 50);

call issue_tickets('Beira-Rio', date '2024-07-27', 1000, 50);
call issue_tickets('Allianz Parque', date '2024-07-27', 1000, 50);
call issue_tickets('Arena Corinthians', date '2024-07-27', 1000, 50);
call issue_tickets('Nilton Santos', date '2024-07-27', 1000, 50);
call issue_tickets('Maracana', date '2024-07-27', 1000, 50);


call issue_tickets('Maracana', date '2024-08-10', 1000, 50);
call issue_tickets('Vila Belmiro', date '2024-08-10', 1000, 50);
call issue_tickets('Morumbi', date '2024-08-10', 1000, 50);
call issue_tickets('Sao Januario', date '2024-08-10', 1000, 50);
call issue_tickets('Arena do Gremio', date '2024-08-10', 1000, 50);

call issue_tickets('Beira-Rio', date '2024-08-17', 1000, 50);
call issue_tickets('Allianz Parque', date '2024-08-17', 1000, 50);
call issue_tickets('Arena Corinthians', date '2024-08-17', 1000, 50);
call issue_tickets('Nilton Santos', date '2024-08-17', 1000, 50);
call issue_tickets('Mineirao', date '2024-08-17', 1000, 50);

call issue_tickets('Maracana', date '2024-09-24', 1000, 50);
call issue_tickets('Vila Belmiro', date '2024-09-24', 1000, 50);
call issue_tickets('Morumbi', date '2024-09-24', 1000, 50);
call issue_tickets('Sao Januario', date '2024-09-24', 1000, 50);
call issue_tickets('Nilton Santos', date '2024-09-24', 1000, 50);

call issue_tickets('Beira-Rio', date '2024-10-01', 1000, 50);
call issue_tickets('Allianz Parque', date '2024-10-01', 1000, 50);
call issue_tickets('Arena Corinthians', date '2024-10-01', 1000, 50);
call issue_tickets('Nilton Santos', date '2024-10-01', 1000, 50);
call issue_tickets('Mineirao', date '2024-10-01', 1000, 50);

call issue_tickets('Maracana', date '2024-10-08', 1000, 50);
call issue_tickets('Allianz Parque', date '2024-10-08', 1000, 50);
call issue_tickets('Morumbi', date '2024-10-08', 1000, 50);
call issue_tickets('Sao Januario', date '2024-10-08', 1000, 50);
call issue_tickets('Nilton Santos', date '2024-10-08', 1000, 50);

call issue_tickets('Beira-Rio', date '2024-10-15', 1000, 50);
call issue_tickets('Allianz Parque', date '2024-10-15', 1000, 50);
call issue_tickets('Arena Corinthians', date '2024-10-15', 1000, 50);
call issue_tickets('Nilton Santos', date '2024-10-15', 1000, 50);
call issue_tickets('Mineirao', date '2024-10-15', 1000, 50);

call issue_tickets('Maracana', date '2024-11-22', 1000, 50);
call issue_tickets('Vila Belmiro', date '2024-11-22', 1000, 50);
call issue_tickets('Morumbi', date '2024-11-22', 1000, 50);
call issue_tickets('Sao Januario', date '2024-11-22', 1000, 50);
call issue_tickets('Arena do Gremio', date '2024-11-22', 1000, 50);

call issue_tickets('Beira-Rio', date '2024-11-29', 1000, 50);
call issue_tickets('Allianz Parque', date '2024-11-29', 1000, 50);
call issue_tickets('Arena Corinthians', date '2024-11-29', 1000, 50);
call issue_tickets('Nilton Santos', date '2024-11-29', 1000, 50);
call issue_tickets('Mineirao', date '2024-11-29', 1000, 50);

call issue_tickets('Maracana', date '2024-12-06', 1000, 50);
call issue_tickets('Vila Belmiro', date '2024-12-06', 1000, 50);
call issue_tickets('Morumbi', date '2024-12-06', 1000, 50);
call issue_tickets('Sao Januario', date '2024-12-06', 1000, 50);
call issue_tickets('Arena do Gremio', date '2024-12-06', 1000, 50);

call issue_tickets('Beira-Rio', date '2024-12-13', 1000, 50);
call issue_tickets('Allianz Parque', date '2024-12-13', 1000, 50);
call issue_tickets('Arena Corinthians', date '2024-12-13', 1000, 50);
call issue_tickets('Nilton Santos', date '2024-12-13', 1000, 50);
call issue_tickets('Mineirao', date '2024-12-13', 1000, 50);

call issue_tickets('Maracana', date '2024-12-20', 1000, 50);
call issue_tickets('Vila Belmiro', date '2024-12-20', 1000, 50);
call issue_tickets('Morumbi', date '2024-12-20', 1000, 50);
call issue_tickets('Sao Januario', date '2024-12-20', 1000, 50);
call issue_tickets('Arena do Gremio', date '2024-12-20', 1000, 50);


--select * from tickets;
--select * from matches;
--select * from seasons;

