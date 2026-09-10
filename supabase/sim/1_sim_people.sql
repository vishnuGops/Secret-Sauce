-- 1_sim_people.sql — GENERATED FILE. DO NOT EDIT BY HAND.
--
-- Source: simData/people.json  ·  Generator: tool/sim.dart
-- Regenerate with `melos run sim:gen`; `melos run sim:check` fails if this
-- file is stale.
--
-- The name and bio pools every simulated profile is drawn from. Given and
-- family names are drawn from the SAME locale for one actor, so a generated
-- name reads as a name rather than a two-culture collage, and a bio's
-- `{cuisine}` is filled from that same locale.
--
-- These rows used to be `array[…]` literals inside 2_sim_generate.sql. Moving
-- them out is not tidying: content inside a `do $$ declare` block cannot be
-- validated, cannot be diffed usefully, and cannot be extended without editing
-- the generator that draws from it.
--
-- Everything lives in schema `sim`, never `public` (B026). Standalone and
-- idempotent: it declares its own tables with `if not exists` — 0_sim_schema
-- declares them too, and whichever runs first wins — upserts by natural key so
-- a content edit propagates, and deletes what the source file no longer has.
-- Contains no credentials and creates no accounts.

create schema if not exists sim;

create table if not exists sim.locale (
  code         text primary key,
  n            int  not null,
  label        text not null,
  cuisine      text not null,
  given_count  int  not null,
  family_count int  not null
);

create table if not exists sim.person_name (
  locale text not null,
  kind   text not null check (kind in ('given', 'family')),
  n      int  not null,
  name   text not null,
  primary key (locale, kind, n)
);

create table if not exists sim.bio (
  n        int primary key,
  template text not null
);

do $grants$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on schema sim from anon, authenticated';
    execute 'revoke all on all tables in schema sim from anon, authenticated';
  end if;
end $grants$;

-- --------------------------------------------------------------------------
-- 17 locales. `n` is the dense 1..L draw index, so an actor picks
-- a tradition with one sim.rand_int() and no scan.
-- --------------------------------------------------------------------------

insert into sim.locale (code, n, label, cuisine, given_count, family_count) values
  ($sp$anglophone$sp$, 1, $sp$British & Irish$sp$, $sp$British$sp$, 16, 16)
on conflict (code) do update set
  n = excluded.n, label = excluded.label,
  cuisine = excluded.cuisine,
  given_count = excluded.given_count,
  family_count = excluded.family_count;

insert into sim.locale (code, n, label, cuisine, given_count, family_count) values
  ($sp$french$sp$, 2, $sp$French$sp$, $sp$French$sp$, 16, 16)
on conflict (code) do update set
  n = excluded.n, label = excluded.label,
  cuisine = excluded.cuisine,
  given_count = excluded.given_count,
  family_count = excluded.family_count;

insert into sim.locale (code, n, label, cuisine, given_count, family_count) values
  ($sp$italian$sp$, 3, $sp$Italian$sp$, $sp$Italian$sp$, 16, 16)
on conflict (code) do update set
  n = excluded.n, label = excluded.label,
  cuisine = excluded.cuisine,
  given_count = excluded.given_count,
  family_count = excluded.family_count;

insert into sim.locale (code, n, label, cuisine, given_count, family_count) values
  ($sp$iberian$sp$, 4, $sp$Spanish$sp$, $sp$Spanish$sp$, 16, 16)
on conflict (code) do update set
  n = excluded.n, label = excluded.label,
  cuisine = excluded.cuisine,
  given_count = excluded.given_count,
  family_count = excluded.family_count;

insert into sim.locale (code, n, label, cuisine, given_count, family_count) values
  ($sp$mexican$sp$, 5, $sp$Mexican$sp$, $sp$Mexican$sp$, 16, 16)
on conflict (code) do update set
  n = excluded.n, label = excluded.label,
  cuisine = excluded.cuisine,
  given_count = excluded.given_count,
  family_count = excluded.family_count;

insert into sim.locale (code, n, label, cuisine, given_count, family_count) values
  ($sp$brazilian$sp$, 6, $sp$Brazilian$sp$, $sp$Brazilian$sp$, 16, 16)
on conflict (code) do update set
  n = excluded.n, label = excluded.label,
  cuisine = excluded.cuisine,
  given_count = excluded.given_count,
  family_count = excluded.family_count;

insert into sim.locale (code, n, label, cuisine, given_count, family_count) values
  ($sp$nordic$sp$, 7, $sp$Nordic$sp$, $sp$Nordic$sp$, 16, 16)
on conflict (code) do update set
  n = excluded.n, label = excluded.label,
  cuisine = excluded.cuisine,
  given_count = excluded.given_count,
  family_count = excluded.family_count;

insert into sim.locale (code, n, label, cuisine, given_count, family_count) values
  ($sp$slavic$sp$, 8, $sp$Russian (Cyrillic)$sp$, $sp$Russian$sp$, 16, 16)
on conflict (code) do update set
  n = excluded.n, label = excluded.label,
  cuisine = excluded.cuisine,
  given_count = excluded.given_count,
  family_count = excluded.family_count;

insert into sim.locale (code, n, label, cuisine, given_count, family_count) values
  ($sp$greek$sp$, 9, $sp$Greek$sp$, $sp$Greek$sp$, 16, 16)
on conflict (code) do update set
  n = excluded.n, label = excluded.label,
  cuisine = excluded.cuisine,
  given_count = excluded.given_count,
  family_count = excluded.family_count;

insert into sim.locale (code, n, label, cuisine, given_count, family_count) values
  ($sp$turkish$sp$, 10, $sp$Turkish$sp$, $sp$Turkish$sp$, 16, 16)
on conflict (code) do update set
  n = excluded.n, label = excluded.label,
  cuisine = excluded.cuisine,
  given_count = excluded.given_count,
  family_count = excluded.family_count;

insert into sim.locale (code, n, label, cuisine, given_count, family_count) values
  ($sp$levantine$sp$, 11, $sp$Levantine (Arabic, RTL)$sp$, $sp$Levantine$sp$, 16, 16)
on conflict (code) do update set
  n = excluded.n, label = excluded.label,
  cuisine = excluded.cuisine,
  given_count = excluded.given_count,
  family_count = excluded.family_count;

insert into sim.locale (code, n, label, cuisine, given_count, family_count) values
  ($sp$persian$sp$, 12, $sp$Persian$sp$, $sp$Persian$sp$, 16, 16)
on conflict (code) do update set
  n = excluded.n, label = excluded.label,
  cuisine = excluded.cuisine,
  given_count = excluded.given_count,
  family_count = excluded.family_count;

insert into sim.locale (code, n, label, cuisine, given_count, family_count) values
  ($sp$west-african$sp$, 13, $sp$West African$sp$, $sp$West African$sp$, 16, 16)
on conflict (code) do update set
  n = excluded.n, label = excluded.label,
  cuisine = excluded.cuisine,
  given_count = excluded.given_count,
  family_count = excluded.family_count;

insert into sim.locale (code, n, label, cuisine, given_count, family_count) values
  ($sp$ethiopian$sp$, 14, $sp$Ethiopian$sp$, $sp$Ethiopian$sp$, 16, 16)
on conflict (code) do update set
  n = excluded.n, label = excluded.label,
  cuisine = excluded.cuisine,
  given_count = excluded.given_count,
  family_count = excluded.family_count;

insert into sim.locale (code, n, label, cuisine, given_count, family_count) values
  ($sp$south-asian$sp$, 15, $sp$South Asian$sp$, $sp$Indian$sp$, 16, 16)
on conflict (code) do update set
  n = excluded.n, label = excluded.label,
  cuisine = excluded.cuisine,
  given_count = excluded.given_count,
  family_count = excluded.family_count;

insert into sim.locale (code, n, label, cuisine, given_count, family_count) values
  ($sp$chinese$sp$, 16, $sp$Chinese$sp$, $sp$Chinese$sp$, 16, 16)
on conflict (code) do update set
  n = excluded.n, label = excluded.label,
  cuisine = excluded.cuisine,
  given_count = excluded.given_count,
  family_count = excluded.family_count;

insert into sim.locale (code, n, label, cuisine, given_count, family_count) values
  ($sp$japanese$sp$, 17, $sp$Japanese$sp$, $sp$Japanese$sp$, 16, 16)
on conflict (code) do update set
  n = excluded.n, label = excluded.label,
  cuisine = excluded.cuisine,
  given_count = excluded.given_count,
  family_count = excluded.family_count;

-- --------------------------------------------------------------------------
-- The names, dense 1..count within each (locale, kind).
-- --------------------------------------------------------------------------

-- British & Irish (anglophone) — given
insert into sim.person_name (locale, kind, n, name) values
  ($sp$anglophone$sp$, $sp$given$sp$, 1, $sp$Alice$sp$),
  ($sp$anglophone$sp$, $sp$given$sp$, 2, $sp$Bernard$sp$),
  ($sp$anglophone$sp$, $sp$given$sp$, 3, $sp$Clara$sp$),
  ($sp$anglophone$sp$, $sp$given$sp$, 4, $sp$Duncan$sp$),
  ($sp$anglophone$sp$, $sp$given$sp$, 5, $sp$Eleanor$sp$),
  ($sp$anglophone$sp$, $sp$given$sp$, 6, $sp$Finn$sp$),
  ($sp$anglophone$sp$, $sp$given$sp$, 7, $sp$Gemma$sp$),
  ($sp$anglophone$sp$, $sp$given$sp$, 8, $sp$Harold$sp$),
  ($sp$anglophone$sp$, $sp$given$sp$, 9, $sp$Imogen$sp$),
  ($sp$anglophone$sp$, $sp$given$sp$, 10, $sp$Jasper$sp$),
  ($sp$anglophone$sp$, $sp$given$sp$, 11, $sp$Katherine$sp$),
  ($sp$anglophone$sp$, $sp$given$sp$, 12, $sp$Liam$sp$),
  ($sp$anglophone$sp$, $sp$given$sp$, 13, $sp$Martha$sp$),
  ($sp$anglophone$sp$, $sp$given$sp$, 14, $sp$Niall$sp$),
  ($sp$anglophone$sp$, $sp$given$sp$, 15, $sp$Orla$sp$),
  ($sp$anglophone$sp$, $sp$given$sp$, 16, $sp$Peter$sp$)
on conflict (locale, kind, n) do update set name = excluded.name;

-- British & Irish (anglophone) — family
insert into sim.person_name (locale, kind, n, name) values
  ($sp$anglophone$sp$, $sp$family$sp$, 1, $sp$Ashworth$sp$),
  ($sp$anglophone$sp$, $sp$family$sp$, 2, $sp$Barlow$sp$),
  ($sp$anglophone$sp$, $sp$family$sp$, 3, $sp$Carmichael$sp$),
  ($sp$anglophone$sp$, $sp$family$sp$, 4, $sp$Doyle$sp$),
  ($sp$anglophone$sp$, $sp$family$sp$, 5, $sp$Ellis$sp$),
  ($sp$anglophone$sp$, $sp$family$sp$, 6, $sp$Fairweather$sp$),
  ($sp$anglophone$sp$, $sp$family$sp$, 7, $sp$Gallagher$sp$),
  ($sp$anglophone$sp$, $sp$family$sp$, 8, $sp$Hollis$sp$),
  ($sp$anglophone$sp$, $sp$family$sp$, 9, $sp$Ingram$sp$),
  ($sp$anglophone$sp$, $sp$family$sp$, 10, $sp$Jarvis$sp$),
  ($sp$anglophone$sp$, $sp$family$sp$, 11, $sp$Kirkby$sp$),
  ($sp$anglophone$sp$, $sp$family$sp$, 12, $sp$Lomax$sp$),
  ($sp$anglophone$sp$, $sp$family$sp$, 13, $sp$Mansfield$sp$),
  ($sp$anglophone$sp$, $sp$family$sp$, 14, $sp$Nolan$sp$),
  ($sp$anglophone$sp$, $sp$family$sp$, 15, $sp$Prentice$sp$),
  ($sp$anglophone$sp$, $sp$family$sp$, 16, $sp$Quigley$sp$)
on conflict (locale, kind, n) do update set name = excluded.name;

-- French (french) — given
insert into sim.person_name (locale, kind, n, name) values
  ($sp$french$sp$, $sp$given$sp$, 1, $sp$Amélie$sp$),
  ($sp$french$sp$, $sp$given$sp$, 2, $sp$Baptiste$sp$),
  ($sp$french$sp$, $sp$given$sp$, 3, $sp$Camille$sp$),
  ($sp$french$sp$, $sp$given$sp$, 4, $sp$Damien$sp$),
  ($sp$french$sp$, $sp$given$sp$, 5, $sp$Élodie$sp$),
  ($sp$french$sp$, $sp$given$sp$, 6, $sp$Fabien$sp$),
  ($sp$french$sp$, $sp$given$sp$, 7, $sp$Gaëlle$sp$),
  ($sp$french$sp$, $sp$given$sp$, 8, $sp$Hugo$sp$),
  ($sp$french$sp$, $sp$given$sp$, 9, $sp$Inès$sp$),
  ($sp$french$sp$, $sp$given$sp$, 10, $sp$Julien$sp$),
  ($sp$french$sp$, $sp$given$sp$, 11, $sp$Léa$sp$),
  ($sp$french$sp$, $sp$given$sp$, 12, $sp$Mathieu$sp$),
  ($sp$french$sp$, $sp$given$sp$, 13, $sp$Noémie$sp$),
  ($sp$french$sp$, $sp$given$sp$, 14, $sp$Olivier$sp$),
  ($sp$french$sp$, $sp$given$sp$, 15, $sp$Perrine$sp$),
  ($sp$french$sp$, $sp$given$sp$, 16, $sp$Rémi$sp$)
on conflict (locale, kind, n) do update set name = excluded.name;

-- French (french) — family
insert into sim.person_name (locale, kind, n, name) values
  ($sp$french$sp$, $sp$family$sp$, 1, $sp$Anceau$sp$),
  ($sp$french$sp$, $sp$family$sp$, 2, $sp$Bourdon$sp$),
  ($sp$french$sp$, $sp$family$sp$, 3, $sp$Chevalier$sp$),
  ($sp$french$sp$, $sp$family$sp$, 4, $sp$Delacroix$sp$),
  ($sp$french$sp$, $sp$family$sp$, 5, $sp$Ferrand$sp$),
  ($sp$french$sp$, $sp$family$sp$, 6, $sp$Girard$sp$),
  ($sp$french$sp$, $sp$family$sp$, 7, $sp$Hubert$sp$),
  ($sp$french$sp$, $sp$family$sp$, 8, $sp$Lacroix$sp$),
  ($sp$french$sp$, $sp$family$sp$, 9, $sp$Marchand$sp$),
  ($sp$french$sp$, $sp$family$sp$, 10, $sp$Noiret$sp$),
  ($sp$french$sp$, $sp$family$sp$, 11, $sp$Perrin$sp$),
  ($sp$french$sp$, $sp$family$sp$, 12, $sp$Quesnel$sp$),
  ($sp$french$sp$, $sp$family$sp$, 13, $sp$Rossignol$sp$),
  ($sp$french$sp$, $sp$family$sp$, 14, $sp$Sauvage$sp$),
  ($sp$french$sp$, $sp$family$sp$, 15, $sp$Thibault$sp$),
  ($sp$french$sp$, $sp$family$sp$, 16, $sp$Vasseur$sp$)
on conflict (locale, kind, n) do update set name = excluded.name;

-- Italian (italian) — given
insert into sim.person_name (locale, kind, n, name) values
  ($sp$italian$sp$, $sp$given$sp$, 1, $sp$Alessia$sp$),
  ($sp$italian$sp$, $sp$given$sp$, 2, $sp$Bruno$sp$),
  ($sp$italian$sp$, $sp$given$sp$, 3, $sp$Chiara$sp$),
  ($sp$italian$sp$, $sp$given$sp$, 4, $sp$Davide$sp$),
  ($sp$italian$sp$, $sp$given$sp$, 5, $sp$Elena$sp$),
  ($sp$italian$sp$, $sp$given$sp$, 6, $sp$Fabrizio$sp$),
  ($sp$italian$sp$, $sp$given$sp$, 7, $sp$Giulia$sp$),
  ($sp$italian$sp$, $sp$given$sp$, 8, $sp$Iacopo$sp$),
  ($sp$italian$sp$, $sp$given$sp$, 9, $sp$Lorenzo$sp$),
  ($sp$italian$sp$, $sp$given$sp$, 10, $sp$Marta$sp$),
  ($sp$italian$sp$, $sp$given$sp$, 11, $sp$Nicolò$sp$),
  ($sp$italian$sp$, $sp$given$sp$, 12, $sp$Ornella$sp$),
  ($sp$italian$sp$, $sp$given$sp$, 13, $sp$Pietro$sp$),
  ($sp$italian$sp$, $sp$given$sp$, 14, $sp$Rosalia$sp$),
  ($sp$italian$sp$, $sp$given$sp$, 15, $sp$Stefano$sp$),
  ($sp$italian$sp$, $sp$given$sp$, 16, $sp$Valentina$sp$)
on conflict (locale, kind, n) do update set name = excluded.name;

-- Italian (italian) — family
insert into sim.person_name (locale, kind, n, name) values
  ($sp$italian$sp$, $sp$family$sp$, 1, $sp$Barbieri$sp$),
  ($sp$italian$sp$, $sp$family$sp$, 2, $sp$Colombo$sp$),
  ($sp$italian$sp$, $sp$family$sp$, 3, $sp$D'Amico$sp$),
  ($sp$italian$sp$, $sp$family$sp$, 4, $sp$Esposito$sp$),
  ($sp$italian$sp$, $sp$family$sp$, 5, $sp$Ferrari$sp$),
  ($sp$italian$sp$, $sp$family$sp$, 6, $sp$Gallo$sp$),
  ($sp$italian$sp$, $sp$family$sp$, 7, $sp$Lombardi$sp$),
  ($sp$italian$sp$, $sp$family$sp$, 8, $sp$Marchetti$sp$),
  ($sp$italian$sp$, $sp$family$sp$, 9, $sp$Neri$sp$),
  ($sp$italian$sp$, $sp$family$sp$, 10, $sp$Orlando$sp$),
  ($sp$italian$sp$, $sp$family$sp$, 11, $sp$Pellegrini$sp$),
  ($sp$italian$sp$, $sp$family$sp$, 12, $sp$Rizzo$sp$),
  ($sp$italian$sp$, $sp$family$sp$, 13, $sp$Santoro$sp$),
  ($sp$italian$sp$, $sp$family$sp$, 14, $sp$Toscano$sp$),
  ($sp$italian$sp$, $sp$family$sp$, 15, $sp$Vitale$sp$),
  ($sp$italian$sp$, $sp$family$sp$, 16, $sp$Zanetti$sp$)
on conflict (locale, kind, n) do update set name = excluded.name;

-- Spanish (iberian) — given
insert into sim.person_name (locale, kind, n, name) values
  ($sp$iberian$sp$, $sp$given$sp$, 1, $sp$Alba$sp$),
  ($sp$iberian$sp$, $sp$given$sp$, 2, $sp$Borja$sp$),
  ($sp$iberian$sp$, $sp$given$sp$, 3, $sp$Candela$sp$),
  ($sp$iberian$sp$, $sp$given$sp$, 4, $sp$Diego$sp$),
  ($sp$iberian$sp$, $sp$given$sp$, 5, $sp$Estela$sp$),
  ($sp$iberian$sp$, $sp$given$sp$, 6, $sp$Fernando$sp$),
  ($sp$iberian$sp$, $sp$given$sp$, 7, $sp$Gonzalo$sp$),
  ($sp$iberian$sp$, $sp$given$sp$, 8, $sp$Inma$sp$),
  ($sp$iberian$sp$, $sp$given$sp$, 9, $sp$Javier$sp$),
  ($sp$iberian$sp$, $sp$given$sp$, 10, $sp$Lucía$sp$),
  ($sp$iberian$sp$, $sp$given$sp$, 11, $sp$Manuel$sp$),
  ($sp$iberian$sp$, $sp$given$sp$, 12, $sp$Nuria$sp$),
  ($sp$iberian$sp$, $sp$given$sp$, 13, $sp$Óscar$sp$),
  ($sp$iberian$sp$, $sp$given$sp$, 14, $sp$Paula$sp$),
  ($sp$iberian$sp$, $sp$given$sp$, 15, $sp$Rocío$sp$),
  ($sp$iberian$sp$, $sp$given$sp$, 16, $sp$Sergio$sp$)
on conflict (locale, kind, n) do update set name = excluded.name;

-- Spanish (iberian) — family
insert into sim.person_name (locale, kind, n, name) values
  ($sp$iberian$sp$, $sp$family$sp$, 1, $sp$Arribas$sp$),
  ($sp$iberian$sp$, $sp$family$sp$, 2, $sp$Beltrán$sp$),
  ($sp$iberian$sp$, $sp$family$sp$, 3, $sp$Cabrera$sp$),
  ($sp$iberian$sp$, $sp$family$sp$, 4, $sp$Delgado$sp$),
  ($sp$iberian$sp$, $sp$family$sp$, 5, $sp$Escudero$sp$),
  ($sp$iberian$sp$, $sp$family$sp$, 6, $sp$Fuentes$sp$),
  ($sp$iberian$sp$, $sp$family$sp$, 7, $sp$Gallardo$sp$),
  ($sp$iberian$sp$, $sp$family$sp$, 8, $sp$Herrera$sp$),
  ($sp$iberian$sp$, $sp$family$sp$, 9, $sp$Iglesias$sp$),
  ($sp$iberian$sp$, $sp$family$sp$, 10, $sp$Jiménez$sp$),
  ($sp$iberian$sp$, $sp$family$sp$, 11, $sp$Lozano$sp$),
  ($sp$iberian$sp$, $sp$family$sp$, 12, $sp$Montero$sp$),
  ($sp$iberian$sp$, $sp$family$sp$, 13, $sp$Navarro$sp$),
  ($sp$iberian$sp$, $sp$family$sp$, 14, $sp$Peláez$sp$),
  ($sp$iberian$sp$, $sp$family$sp$, 15, $sp$Quintero$sp$),
  ($sp$iberian$sp$, $sp$family$sp$, 16, $sp$Vega$sp$)
on conflict (locale, kind, n) do update set name = excluded.name;

-- Mexican (mexican) — given
insert into sim.person_name (locale, kind, n, name) values
  ($sp$mexican$sp$, $sp$given$sp$, 1, $sp$Alejandra$sp$),
  ($sp$mexican$sp$, $sp$given$sp$, 2, $sp$Bernardo$sp$),
  ($sp$mexican$sp$, $sp$given$sp$, 3, $sp$Citlali$sp$),
  ($sp$mexican$sp$, $sp$given$sp$, 4, $sp$Domingo$sp$),
  ($sp$mexican$sp$, $sp$given$sp$, 5, $sp$Elvia$sp$),
  ($sp$mexican$sp$, $sp$given$sp$, 6, $sp$Fausto$sp$),
  ($sp$mexican$sp$, $sp$given$sp$, 7, $sp$Guadalupe$sp$),
  ($sp$mexican$sp$, $sp$given$sp$, 8, $sp$Héctor$sp$),
  ($sp$mexican$sp$, $sp$given$sp$, 9, $sp$Itzel$sp$),
  ($sp$mexican$sp$, $sp$given$sp$, 10, $sp$Joaquín$sp$),
  ($sp$mexican$sp$, $sp$given$sp$, 11, $sp$Lupita$sp$),
  ($sp$mexican$sp$, $sp$given$sp$, 12, $sp$Mauricio$sp$),
  ($sp$mexican$sp$, $sp$given$sp$, 13, $sp$Nayeli$sp$),
  ($sp$mexican$sp$, $sp$given$sp$, 14, $sp$Ofelia$sp$),
  ($sp$mexican$sp$, $sp$given$sp$, 15, $sp$Rodrigo$sp$),
  ($sp$mexican$sp$, $sp$given$sp$, 16, $sp$Xóchitl$sp$)
on conflict (locale, kind, n) do update set name = excluded.name;

-- Mexican (mexican) — family
insert into sim.person_name (locale, kind, n, name) values
  ($sp$mexican$sp$, $sp$family$sp$, 1, $sp$Alcántara$sp$),
  ($sp$mexican$sp$, $sp$family$sp$, 2, $sp$Barragán$sp$),
  ($sp$mexican$sp$, $sp$family$sp$, 3, $sp$Cervantes$sp$),
  ($sp$mexican$sp$, $sp$family$sp$, 4, $sp$Domínguez$sp$),
  ($sp$mexican$sp$, $sp$family$sp$, 5, $sp$Escamilla$sp$),
  ($sp$mexican$sp$, $sp$family$sp$, 6, $sp$Figueroa$sp$),
  ($sp$mexican$sp$, $sp$family$sp$, 7, $sp$Guzmán$sp$),
  ($sp$mexican$sp$, $sp$family$sp$, 8, $sp$Hinojosa$sp$),
  ($sp$mexican$sp$, $sp$family$sp$, 9, $sp$Ibarra$sp$),
  ($sp$mexican$sp$, $sp$family$sp$, 10, $sp$Juárez$sp$),
  ($sp$mexican$sp$, $sp$family$sp$, 11, $sp$Lozada$sp$),
  ($sp$mexican$sp$, $sp$family$sp$, 12, $sp$Mendoza$sp$),
  ($sp$mexican$sp$, $sp$family$sp$, 13, $sp$Nájera$sp$),
  ($sp$mexican$sp$, $sp$family$sp$, 14, $sp$Orozco$sp$),
  ($sp$mexican$sp$, $sp$family$sp$, 15, $sp$Pacheco$sp$),
  ($sp$mexican$sp$, $sp$family$sp$, 16, $sp$Zamudio$sp$)
on conflict (locale, kind, n) do update set name = excluded.name;

-- Brazilian (brazilian) — given
insert into sim.person_name (locale, kind, n, name) values
  ($sp$brazilian$sp$, $sp$given$sp$, 1, $sp$Ana$sp$),
  ($sp$brazilian$sp$, $sp$given$sp$, 2, $sp$Bruna$sp$),
  ($sp$brazilian$sp$, $sp$given$sp$, 3, $sp$Caio$sp$),
  ($sp$brazilian$sp$, $sp$given$sp$, 4, $sp$Daniela$sp$),
  ($sp$brazilian$sp$, $sp$given$sp$, 5, $sp$Eduardo$sp$),
  ($sp$brazilian$sp$, $sp$given$sp$, 6, $sp$Fernanda$sp$),
  ($sp$brazilian$sp$, $sp$given$sp$, 7, $sp$Gustavo$sp$),
  ($sp$brazilian$sp$, $sp$given$sp$, 8, $sp$Heloísa$sp$),
  ($sp$brazilian$sp$, $sp$given$sp$, 9, $sp$Igor$sp$),
  ($sp$brazilian$sp$, $sp$given$sp$, 10, $sp$Juliana$sp$),
  ($sp$brazilian$sp$, $sp$given$sp$, 11, $sp$Lucas$sp$),
  ($sp$brazilian$sp$, $sp$given$sp$, 12, $sp$Mariana$sp$),
  ($sp$brazilian$sp$, $sp$given$sp$, 13, $sp$Otávio$sp$),
  ($sp$brazilian$sp$, $sp$given$sp$, 14, $sp$Priscila$sp$),
  ($sp$brazilian$sp$, $sp$given$sp$, 15, $sp$Rafael$sp$),
  ($sp$brazilian$sp$, $sp$given$sp$, 16, $sp$Thiago$sp$)
on conflict (locale, kind, n) do update set name = excluded.name;

-- Brazilian (brazilian) — family
insert into sim.person_name (locale, kind, n, name) values
  ($sp$brazilian$sp$, $sp$family$sp$, 1, $sp$Almeida$sp$),
  ($sp$brazilian$sp$, $sp$family$sp$, 2, $sp$Barbosa$sp$),
  ($sp$brazilian$sp$, $sp$family$sp$, 3, $sp$Carvalho$sp$),
  ($sp$brazilian$sp$, $sp$family$sp$, 4, $sp$Duarte$sp$),
  ($sp$brazilian$sp$, $sp$family$sp$, 5, $sp$Esteves$sp$),
  ($sp$brazilian$sp$, $sp$family$sp$, 6, $sp$Fonseca$sp$),
  ($sp$brazilian$sp$, $sp$family$sp$, 7, $sp$Gonçalves$sp$),
  ($sp$brazilian$sp$, $sp$family$sp$, 8, $sp$Lacerda$sp$),
  ($sp$brazilian$sp$, $sp$family$sp$, 9, $sp$Machado$sp$),
  ($sp$brazilian$sp$, $sp$family$sp$, 10, $sp$Nogueira$sp$),
  ($sp$brazilian$sp$, $sp$family$sp$, 11, $sp$Oliveira$sp$),
  ($sp$brazilian$sp$, $sp$family$sp$, 12, $sp$Pinheiro$sp$),
  ($sp$brazilian$sp$, $sp$family$sp$, 13, $sp$Queiroz$sp$),
  ($sp$brazilian$sp$, $sp$family$sp$, 14, $sp$Ribeiro$sp$),
  ($sp$brazilian$sp$, $sp$family$sp$, 15, $sp$Siqueira$sp$),
  ($sp$brazilian$sp$, $sp$family$sp$, 16, $sp$Teixeira$sp$)
on conflict (locale, kind, n) do update set name = excluded.name;

-- Nordic (nordic) — given
insert into sim.person_name (locale, kind, n, name) values
  ($sp$nordic$sp$, $sp$given$sp$, 1, $sp$Annika$sp$),
  ($sp$nordic$sp$, $sp$given$sp$, 2, $sp$Bjørn$sp$),
  ($sp$nordic$sp$, $sp$given$sp$, 3, $sp$Cecilie$sp$),
  ($sp$nordic$sp$, $sp$given$sp$, 4, $sp$Dagny$sp$),
  ($sp$nordic$sp$, $sp$given$sp$, 5, $sp$Einar$sp$),
  ($sp$nordic$sp$, $sp$given$sp$, 6, $sp$Freja$sp$),
  ($sp$nordic$sp$, $sp$given$sp$, 7, $sp$Gustav$sp$),
  ($sp$nordic$sp$, $sp$given$sp$, 8, $sp$Halldór$sp$),
  ($sp$nordic$sp$, $sp$given$sp$, 9, $sp$Ingrid$sp$),
  ($sp$nordic$sp$, $sp$given$sp$, 10, $sp$Jonas$sp$),
  ($sp$nordic$sp$, $sp$given$sp$, 11, $sp$Kaisa$sp$),
  ($sp$nordic$sp$, $sp$given$sp$, 12, $sp$Lars$sp$),
  ($sp$nordic$sp$, $sp$given$sp$, 13, $sp$Mette$sp$),
  ($sp$nordic$sp$, $sp$given$sp$, 14, $sp$Nils$sp$),
  ($sp$nordic$sp$, $sp$given$sp$, 15, $sp$Oskar$sp$),
  ($sp$nordic$sp$, $sp$given$sp$, 16, $sp$Sigrid$sp$)
on conflict (locale, kind, n) do update set name = excluded.name;

-- Nordic (nordic) — family
insert into sim.person_name (locale, kind, n, name) values
  ($sp$nordic$sp$, $sp$family$sp$, 1, $sp$Aalto$sp$),
  ($sp$nordic$sp$, $sp$family$sp$, 2, $sp$Berglund$sp$),
  ($sp$nordic$sp$, $sp$family$sp$, 3, $sp$Christensen$sp$),
  ($sp$nordic$sp$, $sp$family$sp$, 4, $sp$Dahl$sp$),
  ($sp$nordic$sp$, $sp$family$sp$, 5, $sp$Eskildsen$sp$),
  ($sp$nordic$sp$, $sp$family$sp$, 6, $sp$Fredriksen$sp$),
  ($sp$nordic$sp$, $sp$family$sp$, 7, $sp$Grønvold$sp$),
  ($sp$nordic$sp$, $sp$family$sp$, 8, $sp$Hagen$sp$),
  ($sp$nordic$sp$, $sp$family$sp$, 9, $sp$Isaksen$sp$),
  ($sp$nordic$sp$, $sp$family$sp$, 10, $sp$Jokinen$sp$),
  ($sp$nordic$sp$, $sp$family$sp$, 11, $sp$Kristiansen$sp$),
  ($sp$nordic$sp$, $sp$family$sp$, 12, $sp$Lindholm$sp$),
  ($sp$nordic$sp$, $sp$family$sp$, 13, $sp$Mikkelsen$sp$),
  ($sp$nordic$sp$, $sp$family$sp$, 14, $sp$Nyström$sp$),
  ($sp$nordic$sp$, $sp$family$sp$, 15, $sp$Østby$sp$),
  ($sp$nordic$sp$, $sp$family$sp$, 16, $sp$Söderlund$sp$)
on conflict (locale, kind, n) do update set name = excluded.name;

-- Russian (Cyrillic) (slavic) — given
insert into sim.person_name (locale, kind, n, name) values
  ($sp$slavic$sp$, $sp$given$sp$, 1, $sp$Анастасия$sp$),
  ($sp$slavic$sp$, $sp$given$sp$, 2, $sp$Борис$sp$),
  ($sp$slavic$sp$, $sp$given$sp$, 3, $sp$Валентина$sp$),
  ($sp$slavic$sp$, $sp$given$sp$, 4, $sp$Дмитрий$sp$),
  ($sp$slavic$sp$, $sp$given$sp$, 5, $sp$Екатерина$sp$),
  ($sp$slavic$sp$, $sp$given$sp$, 6, $sp$Захар$sp$),
  ($sp$slavic$sp$, $sp$given$sp$, 7, $sp$Ирина$sp$),
  ($sp$slavic$sp$, $sp$given$sp$, 8, $sp$Кирилл$sp$),
  ($sp$slavic$sp$, $sp$given$sp$, 9, $sp$Людмила$sp$),
  ($sp$slavic$sp$, $sp$given$sp$, 10, $sp$Максим$sp$),
  ($sp$slavic$sp$, $sp$given$sp$, 11, $sp$Наталья$sp$),
  ($sp$slavic$sp$, $sp$given$sp$, 12, $sp$Олег$sp$),
  ($sp$slavic$sp$, $sp$given$sp$, 13, $sp$Полина$sp$),
  ($sp$slavic$sp$, $sp$given$sp$, 14, $sp$Руслан$sp$),
  ($sp$slavic$sp$, $sp$given$sp$, 15, $sp$Светлана$sp$),
  ($sp$slavic$sp$, $sp$given$sp$, 16, $sp$Тимур$sp$)
on conflict (locale, kind, n) do update set name = excluded.name;

-- Russian (Cyrillic) (slavic) — family
insert into sim.person_name (locale, kind, n, name) values
  ($sp$slavic$sp$, $sp$family$sp$, 1, $sp$Абрамов$sp$),
  ($sp$slavic$sp$, $sp$family$sp$, 2, $sp$Богданова$sp$),
  ($sp$slavic$sp$, $sp$family$sp$, 3, $sp$Волкова$sp$),
  ($sp$slavic$sp$, $sp$family$sp$, 4, $sp$Гаврилов$sp$),
  ($sp$slavic$sp$, $sp$family$sp$, 5, $sp$Дементьев$sp$),
  ($sp$slavic$sp$, $sp$family$sp$, 6, $sp$Ефимова$sp$),
  ($sp$slavic$sp$, $sp$family$sp$, 7, $sp$Жуков$sp$),
  ($sp$slavic$sp$, $sp$family$sp$, 8, $sp$Зайцева$sp$),
  ($sp$slavic$sp$, $sp$family$sp$, 9, $sp$Кузнецов$sp$),
  ($sp$slavic$sp$, $sp$family$sp$, 10, $sp$Лебедева$sp$),
  ($sp$slavic$sp$, $sp$family$sp$, 11, $sp$Морозов$sp$),
  ($sp$slavic$sp$, $sp$family$sp$, 12, $sp$Никитина$sp$),
  ($sp$slavic$sp$, $sp$family$sp$, 13, $sp$Орлов$sp$),
  ($sp$slavic$sp$, $sp$family$sp$, 14, $sp$Панкратова$sp$),
  ($sp$slavic$sp$, $sp$family$sp$, 15, $sp$Романов$sp$),
  ($sp$slavic$sp$, $sp$family$sp$, 16, $sp$Соколова$sp$)
on conflict (locale, kind, n) do update set name = excluded.name;

-- Greek (greek) — given
insert into sim.person_name (locale, kind, n, name) values
  ($sp$greek$sp$, $sp$given$sp$, 1, $sp$Alexios$sp$),
  ($sp$greek$sp$, $sp$given$sp$, 2, $sp$Despina$sp$),
  ($sp$greek$sp$, $sp$given$sp$, 3, $sp$Eleni$sp$),
  ($sp$greek$sp$, $sp$given$sp$, 4, $sp$Fotis$sp$),
  ($sp$greek$sp$, $sp$given$sp$, 5, $sp$Georgios$sp$),
  ($sp$greek$sp$, $sp$given$sp$, 6, $sp$Ioanna$sp$),
  ($sp$greek$sp$, $sp$given$sp$, 7, $sp$Kostas$sp$),
  ($sp$greek$sp$, $sp$given$sp$, 8, $sp$Lambros$sp$),
  ($sp$greek$sp$, $sp$given$sp$, 9, $sp$Maria$sp$),
  ($sp$greek$sp$, $sp$given$sp$, 10, $sp$Nikos$sp$),
  ($sp$greek$sp$, $sp$given$sp$, 11, $sp$Ourania$sp$),
  ($sp$greek$sp$, $sp$given$sp$, 12, $sp$Panagiotis$sp$),
  ($sp$greek$sp$, $sp$given$sp$, 13, $sp$Rania$sp$),
  ($sp$greek$sp$, $sp$given$sp$, 14, $sp$Sofia$sp$),
  ($sp$greek$sp$, $sp$given$sp$, 15, $sp$Thanasis$sp$),
  ($sp$greek$sp$, $sp$given$sp$, 16, $sp$Vasiliki$sp$)
on conflict (locale, kind, n) do update set name = excluded.name;

-- Greek (greek) — family
insert into sim.person_name (locale, kind, n, name) values
  ($sp$greek$sp$, $sp$family$sp$, 1, $sp$Andreadis$sp$),
  ($sp$greek$sp$, $sp$family$sp$, 2, $sp$Baltas$sp$),
  ($sp$greek$sp$, $sp$family$sp$, 3, $sp$Christopoulos$sp$),
  ($sp$greek$sp$, $sp$family$sp$, 4, $sp$Dimitriou$sp$),
  ($sp$greek$sp$, $sp$family$sp$, 5, $sp$Eleftheriou$sp$),
  ($sp$greek$sp$, $sp$family$sp$, 6, $sp$Fotiadis$sp$),
  ($sp$greek$sp$, $sp$family$sp$, 7, $sp$Georgiou$sp$),
  ($sp$greek$sp$, $sp$family$sp$, 8, $sp$Iliopoulos$sp$),
  ($sp$greek$sp$, $sp$family$sp$, 9, $sp$Kalogeras$sp$),
  ($sp$greek$sp$, $sp$family$sp$, 10, $sp$Lambrakis$sp$),
  ($sp$greek$sp$, $sp$family$sp$, 11, $sp$Makris$sp$),
  ($sp$greek$sp$, $sp$family$sp$, 12, $sp$Nikolaidis$sp$),
  ($sp$greek$sp$, $sp$family$sp$, 13, $sp$Papadopoulos$sp$),
  ($sp$greek$sp$, $sp$family$sp$, 14, $sp$Samaras$sp$),
  ($sp$greek$sp$, $sp$family$sp$, 15, $sp$Theodorou$sp$),
  ($sp$greek$sp$, $sp$family$sp$, 16, $sp$Vlachos$sp$)
on conflict (locale, kind, n) do update set name = excluded.name;

-- Turkish (turkish) — given
insert into sim.person_name (locale, kind, n, name) values
  ($sp$turkish$sp$, $sp$given$sp$, 1, $sp$Ayşe$sp$),
  ($sp$turkish$sp$, $sp$given$sp$, 2, $sp$Burak$sp$),
  ($sp$turkish$sp$, $sp$given$sp$, 3, $sp$Ceren$sp$),
  ($sp$turkish$sp$, $sp$given$sp$, 4, $sp$Deniz$sp$),
  ($sp$turkish$sp$, $sp$given$sp$, 5, $sp$Emre$sp$),
  ($sp$turkish$sp$, $sp$given$sp$, 6, $sp$Fatma$sp$),
  ($sp$turkish$sp$, $sp$given$sp$, 7, $sp$Gökhan$sp$),
  ($sp$turkish$sp$, $sp$given$sp$, 8, $sp$Hülya$sp$),
  ($sp$turkish$sp$, $sp$given$sp$, 9, $sp$İbrahim$sp$),
  ($sp$turkish$sp$, $sp$given$sp$, 10, $sp$Kerem$sp$),
  ($sp$turkish$sp$, $sp$given$sp$, 11, $sp$Leyla$sp$),
  ($sp$turkish$sp$, $sp$given$sp$, 12, $sp$Murat$sp$),
  ($sp$turkish$sp$, $sp$given$sp$, 13, $sp$Nesrin$sp$),
  ($sp$turkish$sp$, $sp$given$sp$, 14, $sp$Özlem$sp$),
  ($sp$turkish$sp$, $sp$given$sp$, 15, $sp$Serkan$sp$),
  ($sp$turkish$sp$, $sp$given$sp$, 16, $sp$Zeynep$sp$)
on conflict (locale, kind, n) do update set name = excluded.name;

-- Turkish (turkish) — family
insert into sim.person_name (locale, kind, n, name) values
  ($sp$turkish$sp$, $sp$family$sp$, 1, $sp$Akgün$sp$),
  ($sp$turkish$sp$, $sp$family$sp$, 2, $sp$Bulut$sp$),
  ($sp$turkish$sp$, $sp$family$sp$, 3, $sp$Çetin$sp$),
  ($sp$turkish$sp$, $sp$family$sp$, 4, $sp$Demirci$sp$),
  ($sp$turkish$sp$, $sp$family$sp$, 5, $sp$Erdem$sp$),
  ($sp$turkish$sp$, $sp$family$sp$, 6, $sp$Fidan$sp$),
  ($sp$turkish$sp$, $sp$family$sp$, 7, $sp$Güneş$sp$),
  ($sp$turkish$sp$, $sp$family$sp$, 8, $sp$Işık$sp$),
  ($sp$turkish$sp$, $sp$family$sp$, 9, $sp$Kaya$sp$),
  ($sp$turkish$sp$, $sp$family$sp$, 10, $sp$Korkmaz$sp$),
  ($sp$turkish$sp$, $sp$family$sp$, 11, $sp$Öztürk$sp$),
  ($sp$turkish$sp$, $sp$family$sp$, 12, $sp$Polat$sp$),
  ($sp$turkish$sp$, $sp$family$sp$, 13, $sp$Şahin$sp$),
  ($sp$turkish$sp$, $sp$family$sp$, 14, $sp$Tekin$sp$),
  ($sp$turkish$sp$, $sp$family$sp$, 15, $sp$Yalçın$sp$),
  ($sp$turkish$sp$, $sp$family$sp$, 16, $sp$Yıldırım$sp$)
on conflict (locale, kind, n) do update set name = excluded.name;

-- Levantine (Arabic, RTL) (levantine) — given
insert into sim.person_name (locale, kind, n, name) values
  ($sp$levantine$sp$, $sp$given$sp$, 1, $sp$أمينة$sp$),
  ($sp$levantine$sp$, $sp$given$sp$, 2, $sp$بشار$sp$),
  ($sp$levantine$sp$, $sp$given$sp$, 3, $sp$دلال$sp$),
  ($sp$levantine$sp$, $sp$given$sp$, 4, $sp$رامي$sp$),
  ($sp$levantine$sp$, $sp$given$sp$, 5, $sp$زينب$sp$),
  ($sp$levantine$sp$, $sp$given$sp$, 6, $sp$سامي$sp$),
  ($sp$levantine$sp$, $sp$given$sp$, 7, $sp$طارق$sp$),
  ($sp$levantine$sp$, $sp$given$sp$, 8, $sp$عبير$sp$),
  ($sp$levantine$sp$, $sp$given$sp$, 9, $sp$فادي$sp$),
  ($sp$levantine$sp$, $sp$given$sp$, 10, $sp$كريم$sp$),
  ($sp$levantine$sp$, $sp$given$sp$, 11, $sp$ليلى$sp$),
  ($sp$levantine$sp$, $sp$given$sp$, 12, $sp$مروان$sp$),
  ($sp$levantine$sp$, $sp$given$sp$, 13, $sp$نادية$sp$),
  ($sp$levantine$sp$, $sp$given$sp$, 14, $sp$هالة$sp$),
  ($sp$levantine$sp$, $sp$given$sp$, 15, $sp$وسيم$sp$),
  ($sp$levantine$sp$, $sp$given$sp$, 16, $sp$يوسف$sp$)
on conflict (locale, kind, n) do update set name = excluded.name;

-- Levantine (Arabic, RTL) (levantine) — family
insert into sim.person_name (locale, kind, n, name) values
  ($sp$levantine$sp$, $sp$family$sp$, 1, $sp$الأحمد$sp$),
  ($sp$levantine$sp$, $sp$family$sp$, 2, $sp$البستاني$sp$),
  ($sp$levantine$sp$, $sp$family$sp$, 3, $sp$الحلبي$sp$),
  ($sp$levantine$sp$, $sp$family$sp$, 4, $sp$الخوري$sp$),
  ($sp$levantine$sp$, $sp$family$sp$, 5, $sp$الدباس$sp$),
  ($sp$levantine$sp$, $sp$family$sp$, 6, $sp$الرفاعي$sp$),
  ($sp$levantine$sp$, $sp$family$sp$, 7, $sp$السمان$sp$),
  ($sp$levantine$sp$, $sp$family$sp$, 8, $sp$الشامي$sp$),
  ($sp$levantine$sp$, $sp$family$sp$, 9, $sp$الصايغ$sp$),
  ($sp$levantine$sp$, $sp$family$sp$, 10, $sp$الطويل$sp$),
  ($sp$levantine$sp$, $sp$family$sp$, 11, $sp$العطار$sp$),
  ($sp$levantine$sp$, $sp$family$sp$, 12, $sp$القاسم$sp$),
  ($sp$levantine$sp$, $sp$family$sp$, 13, $sp$الكيلاني$sp$),
  ($sp$levantine$sp$, $sp$family$sp$, 14, $sp$المصري$sp$),
  ($sp$levantine$sp$, $sp$family$sp$, 15, $sp$النابلسي$sp$),
  ($sp$levantine$sp$, $sp$family$sp$, 16, $sp$الياسين$sp$)
on conflict (locale, kind, n) do update set name = excluded.name;

-- Persian (persian) — given
insert into sim.person_name (locale, kind, n, name) values
  ($sp$persian$sp$, $sp$given$sp$, 1, $sp$Arash$sp$),
  ($sp$persian$sp$, $sp$given$sp$, 2, $sp$Bahar$sp$),
  ($sp$persian$sp$, $sp$given$sp$, 3, $sp$Darioush$sp$),
  ($sp$persian$sp$, $sp$given$sp$, 4, $sp$Elham$sp$),
  ($sp$persian$sp$, $sp$given$sp$, 5, $sp$Farhad$sp$),
  ($sp$persian$sp$, $sp$given$sp$, 6, $sp$Golnaz$sp$),
  ($sp$persian$sp$, $sp$given$sp$, 7, $sp$Hossein$sp$),
  ($sp$persian$sp$, $sp$given$sp$, 8, $sp$Iman$sp$),
  ($sp$persian$sp$, $sp$given$sp$, 9, $sp$Jaleh$sp$),
  ($sp$persian$sp$, $sp$given$sp$, 10, $sp$Kamran$sp$),
  ($sp$persian$sp$, $sp$given$sp$, 11, $sp$Laleh$sp$),
  ($sp$persian$sp$, $sp$given$sp$, 12, $sp$Mehrdad$sp$),
  ($sp$persian$sp$, $sp$given$sp$, 13, $sp$Nasrin$sp$),
  ($sp$persian$sp$, $sp$given$sp$, 14, $sp$Parisa$sp$),
  ($sp$persian$sp$, $sp$given$sp$, 15, $sp$Ramin$sp$),
  ($sp$persian$sp$, $sp$given$sp$, 16, $sp$Shirin$sp$)
on conflict (locale, kind, n) do update set name = excluded.name;

-- Persian (persian) — family
insert into sim.person_name (locale, kind, n, name) values
  ($sp$persian$sp$, $sp$family$sp$, 1, $sp$Ahmadi$sp$),
  ($sp$persian$sp$, $sp$family$sp$, 2, $sp$Bahrami$sp$),
  ($sp$persian$sp$, $sp$family$sp$, 3, $sp$Dadgar$sp$),
  ($sp$persian$sp$, $sp$family$sp$, 4, $sp$Ebrahimi$sp$),
  ($sp$persian$sp$, $sp$family$sp$, 5, $sp$Farahani$sp$),
  ($sp$persian$sp$, $sp$family$sp$, 6, $sp$Ghorbani$sp$),
  ($sp$persian$sp$, $sp$family$sp$, 7, $sp$Hosseini$sp$),
  ($sp$persian$sp$, $sp$family$sp$, 8, $sp$Jafari$sp$),
  ($sp$persian$sp$, $sp$family$sp$, 9, $sp$Kazemi$sp$),
  ($sp$persian$sp$, $sp$family$sp$, 10, $sp$Lotfi$sp$),
  ($sp$persian$sp$, $sp$family$sp$, 11, $sp$Mousavi$sp$),
  ($sp$persian$sp$, $sp$family$sp$, 12, $sp$Nazari$sp$),
  ($sp$persian$sp$, $sp$family$sp$, 13, $sp$Rahimi$sp$),
  ($sp$persian$sp$, $sp$family$sp$, 14, $sp$Sadeghi$sp$),
  ($sp$persian$sp$, $sp$family$sp$, 15, $sp$Tabatabai$sp$),
  ($sp$persian$sp$, $sp$family$sp$, 16, $sp$Zandi$sp$)
on conflict (locale, kind, n) do update set name = excluded.name;

-- West African (west-african) — given
insert into sim.person_name (locale, kind, n, name) values
  ($sp$west-african$sp$, $sp$given$sp$, 1, $sp$Abeni$sp$),
  ($sp$west-african$sp$, $sp$given$sp$, 2, $sp$Chidi$sp$),
  ($sp$west-african$sp$, $sp$given$sp$, 3, $sp$Ekow$sp$),
  ($sp$west-african$sp$, $sp$given$sp$, 4, $sp$Folake$sp$),
  ($sp$west-african$sp$, $sp$given$sp$, 5, $sp$Gozie$sp$),
  ($sp$west-african$sp$, $sp$given$sp$, 6, $sp$Ifeoma$sp$),
  ($sp$west-african$sp$, $sp$given$sp$, 7, $sp$Kwabena$sp$),
  ($sp$west-african$sp$, $sp$given$sp$, 8, $sp$Lanre$sp$),
  ($sp$west-african$sp$, $sp$given$sp$, 9, $sp$Mariama$sp$),
  ($sp$west-african$sp$, $sp$given$sp$, 10, $sp$Nnamdi$sp$),
  ($sp$west-african$sp$, $sp$given$sp$, 11, $sp$Obiageli$sp$),
  ($sp$west-african$sp$, $sp$given$sp$, 12, $sp$Rasheed$sp$),
  ($sp$west-african$sp$, $sp$given$sp$, 13, $sp$Sade$sp$),
  ($sp$west-african$sp$, $sp$given$sp$, 14, $sp$Tunde$sp$),
  ($sp$west-african$sp$, $sp$given$sp$, 15, $sp$Uchenna$sp$),
  ($sp$west-african$sp$, $sp$given$sp$, 16, $sp$Yaa$sp$)
on conflict (locale, kind, n) do update set name = excluded.name;

-- West African (west-african) — family
insert into sim.person_name (locale, kind, n, name) values
  ($sp$west-african$sp$, $sp$family$sp$, 1, $sp$Achebe$sp$),
  ($sp$west-african$sp$, $sp$family$sp$, 2, $sp$Boateng$sp$),
  ($sp$west-african$sp$, $sp$family$sp$, 3, $sp$Chukwu$sp$),
  ($sp$west-african$sp$, $sp$family$sp$, 4, $sp$Danquah$sp$),
  ($sp$west-african$sp$, $sp$family$sp$, 5, $sp$Eze$sp$),
  ($sp$west-african$sp$, $sp$family$sp$, 6, $sp$Frimpong$sp$),
  ($sp$west-african$sp$, $sp$family$sp$, 7, $sp$Gyasi$sp$),
  ($sp$west-african$sp$, $sp$family$sp$, 8, $sp$Ibekwe$sp$),
  ($sp$west-african$sp$, $sp$family$sp$, 9, $sp$Jalloh$sp$),
  ($sp$west-african$sp$, $sp$family$sp$, 10, $sp$Kamara$sp$),
  ($sp$west-african$sp$, $sp$family$sp$, 11, $sp$Lawal$sp$),
  ($sp$west-african$sp$, $sp$family$sp$, 12, $sp$Mensah$sp$),
  ($sp$west-african$sp$, $sp$family$sp$, 13, $sp$Nwosu$sp$),
  ($sp$west-african$sp$, $sp$family$sp$, 14, $sp$Okonjo$sp$),
  ($sp$west-african$sp$, $sp$family$sp$, 15, $sp$Sesay$sp$),
  ($sp$west-african$sp$, $sp$family$sp$, 16, $sp$Yeboah$sp$)
on conflict (locale, kind, n) do update set name = excluded.name;

-- Ethiopian (ethiopian) — given
insert into sim.person_name (locale, kind, n, name) values
  ($sp$ethiopian$sp$, $sp$given$sp$, 1, $sp$Abeba$sp$),
  ($sp$ethiopian$sp$, $sp$given$sp$, 2, $sp$Bekele$sp$),
  ($sp$ethiopian$sp$, $sp$given$sp$, 3, $sp$Dawit$sp$),
  ($sp$ethiopian$sp$, $sp$given$sp$, 4, $sp$Eyob$sp$),
  ($sp$ethiopian$sp$, $sp$given$sp$, 5, $sp$Fikru$sp$),
  ($sp$ethiopian$sp$, $sp$given$sp$, 6, $sp$Genet$sp$),
  ($sp$ethiopian$sp$, $sp$given$sp$, 7, $sp$Hirut$sp$),
  ($sp$ethiopian$sp$, $sp$given$sp$, 8, $sp$Kidist$sp$),
  ($sp$ethiopian$sp$, $sp$given$sp$, 9, $sp$Lemlem$sp$),
  ($sp$ethiopian$sp$, $sp$given$sp$, 10, $sp$Mulugeta$sp$),
  ($sp$ethiopian$sp$, $sp$given$sp$, 11, $sp$Nardos$sp$),
  ($sp$ethiopian$sp$, $sp$given$sp$, 12, $sp$Rahel$sp$),
  ($sp$ethiopian$sp$, $sp$given$sp$, 13, $sp$Selam$sp$),
  ($sp$ethiopian$sp$, $sp$given$sp$, 14, $sp$Tesfaye$sp$),
  ($sp$ethiopian$sp$, $sp$given$sp$, 15, $sp$Wubet$sp$),
  ($sp$ethiopian$sp$, $sp$given$sp$, 16, $sp$Yohannes$sp$)
on conflict (locale, kind, n) do update set name = excluded.name;

-- Ethiopian (ethiopian) — family
insert into sim.person_name (locale, kind, n, name) values
  ($sp$ethiopian$sp$, $sp$family$sp$, 1, $sp$Abera$sp$),
  ($sp$ethiopian$sp$, $sp$family$sp$, 2, $sp$Bogale$sp$),
  ($sp$ethiopian$sp$, $sp$family$sp$, 3, $sp$Desta$sp$),
  ($sp$ethiopian$sp$, $sp$family$sp$, 4, $sp$Endale$sp$),
  ($sp$ethiopian$sp$, $sp$family$sp$, 5, $sp$Fantahun$sp$),
  ($sp$ethiopian$sp$, $sp$family$sp$, 6, $sp$Gebre$sp$),
  ($sp$ethiopian$sp$, $sp$family$sp$, 7, $sp$Haile$sp$),
  ($sp$ethiopian$sp$, $sp$family$sp$, 8, $sp$Kassa$sp$),
  ($sp$ethiopian$sp$, $sp$family$sp$, 9, $sp$Lemma$sp$),
  ($sp$ethiopian$sp$, $sp$family$sp$, 10, $sp$Mekonnen$sp$),
  ($sp$ethiopian$sp$, $sp$family$sp$, 11, $sp$Negash$sp$),
  ($sp$ethiopian$sp$, $sp$family$sp$, 12, $sp$Seyoum$sp$),
  ($sp$ethiopian$sp$, $sp$family$sp$, 13, $sp$Tadesse$sp$),
  ($sp$ethiopian$sp$, $sp$family$sp$, 14, $sp$Wolde$sp$),
  ($sp$ethiopian$sp$, $sp$family$sp$, 15, $sp$Yimer$sp$),
  ($sp$ethiopian$sp$, $sp$family$sp$, 16, $sp$Zewde$sp$)
on conflict (locale, kind, n) do update set name = excluded.name;

-- South Asian (south-asian) — given
insert into sim.person_name (locale, kind, n, name) values
  ($sp$south-asian$sp$, $sp$given$sp$, 1, $sp$Aarti$sp$),
  ($sp$south-asian$sp$, $sp$given$sp$, 2, $sp$Bhavna$sp$),
  ($sp$south-asian$sp$, $sp$given$sp$, 3, $sp$Chetan$sp$),
  ($sp$south-asian$sp$, $sp$given$sp$, 4, $sp$Devika$sp$),
  ($sp$south-asian$sp$, $sp$given$sp$, 5, $sp$Farhan$sp$),
  ($sp$south-asian$sp$, $sp$given$sp$, 6, $sp$Gauri$sp$),
  ($sp$south-asian$sp$, $sp$given$sp$, 7, $sp$Harpreet$sp$),
  ($sp$south-asian$sp$, $sp$given$sp$, 8, $sp$Ishaan$sp$),
  ($sp$south-asian$sp$, $sp$given$sp$, 9, $sp$Jyoti$sp$),
  ($sp$south-asian$sp$, $sp$given$sp$, 10, $sp$Kabir$sp$),
  ($sp$south-asian$sp$, $sp$given$sp$, 11, $sp$Lakshmi$sp$),
  ($sp$south-asian$sp$, $sp$given$sp$, 12, $sp$Manoj$sp$),
  ($sp$south-asian$sp$, $sp$given$sp$, 13, $sp$Nikhil$sp$),
  ($sp$south-asian$sp$, $sp$given$sp$, 14, $sp$Pallavi$sp$),
  ($sp$south-asian$sp$, $sp$given$sp$, 15, $sp$Rukmini$sp$),
  ($sp$south-asian$sp$, $sp$given$sp$, 16, $sp$Sanjay$sp$)
on conflict (locale, kind, n) do update set name = excluded.name;

-- South Asian (south-asian) — family
insert into sim.person_name (locale, kind, n, name) values
  ($sp$south-asian$sp$, $sp$family$sp$, 1, $sp$Agarwal$sp$),
  ($sp$south-asian$sp$, $sp$family$sp$, 2, $sp$Bhattacharya$sp$),
  ($sp$south-asian$sp$, $sp$family$sp$, 3, $sp$Chaudhari$sp$),
  ($sp$south-asian$sp$, $sp$family$sp$, 4, $sp$Deshpande$sp$),
  ($sp$south-asian$sp$, $sp$family$sp$, 5, $sp$Iyer$sp$),
  ($sp$south-asian$sp$, $sp$family$sp$, 6, $sp$Joshi$sp$),
  ($sp$south-asian$sp$, $sp$family$sp$, 7, $sp$Kulkarni$sp$),
  ($sp$south-asian$sp$, $sp$family$sp$, 8, $sp$Menon$sp$),
  ($sp$south-asian$sp$, $sp$family$sp$, 9, $sp$Nair$sp$),
  ($sp$south-asian$sp$, $sp$family$sp$, 10, $sp$Pillai$sp$),
  ($sp$south-asian$sp$, $sp$family$sp$, 11, $sp$Rao$sp$),
  ($sp$south-asian$sp$, $sp$family$sp$, 12, $sp$Sengupta$sp$),
  ($sp$south-asian$sp$, $sp$family$sp$, 13, $sp$Thakur$sp$),
  ($sp$south-asian$sp$, $sp$family$sp$, 14, $sp$Varma$sp$),
  ($sp$south-asian$sp$, $sp$family$sp$, 15, $sp$Wadhwa$sp$),
  ($sp$south-asian$sp$, $sp$family$sp$, 16, $sp$Yadav$sp$)
on conflict (locale, kind, n) do update set name = excluded.name;

-- Chinese (chinese) — given
insert into sim.person_name (locale, kind, n, name) values
  ($sp$chinese$sp$, $sp$given$sp$, 1, $sp$Bingwen$sp$),
  ($sp$chinese$sp$, $sp$given$sp$, 2, $sp$Chunhua$sp$),
  ($sp$chinese$sp$, $sp$given$sp$, 3, $sp$Daiyu$sp$),
  ($sp$chinese$sp$, $sp$given$sp$, 4, $sp$Fenfang$sp$),
  ($sp$chinese$sp$, $sp$given$sp$, 5, $sp$Guiying$sp$),
  ($sp$chinese$sp$, $sp$given$sp$, 6, $sp$Haoran$sp$),
  ($sp$chinese$sp$, $sp$given$sp$, 7, $sp$Jinhai$sp$),
  ($sp$chinese$sp$, $sp$given$sp$, 8, $sp$Lijuan$sp$),
  ($sp$chinese$sp$, $sp$given$sp$, 9, $sp$Meixiang$sp$),
  ($sp$chinese$sp$, $sp$given$sp$, 10, $sp$Ning$sp$),
  ($sp$chinese$sp$, $sp$given$sp$, 11, $sp$Qiang$sp$),
  ($sp$chinese$sp$, $sp$given$sp$, 12, $sp$Ruolan$sp$),
  ($sp$chinese$sp$, $sp$given$sp$, 13, $sp$Shufen$sp$),
  ($sp$chinese$sp$, $sp$given$sp$, 14, $sp$Weiming$sp$),
  ($sp$chinese$sp$, $sp$given$sp$, 15, $sp$Xiulan$sp$),
  ($sp$chinese$sp$, $sp$given$sp$, 16, $sp$Yanmei$sp$)
on conflict (locale, kind, n) do update set name = excluded.name;

-- Chinese (chinese) — family
insert into sim.person_name (locale, kind, n, name) values
  ($sp$chinese$sp$, $sp$family$sp$, 1, $sp$Cai$sp$),
  ($sp$chinese$sp$, $sp$family$sp$, 2, $sp$Deng$sp$),
  ($sp$chinese$sp$, $sp$family$sp$, 3, $sp$Feng$sp$),
  ($sp$chinese$sp$, $sp$family$sp$, 4, $sp$Guo$sp$),
  ($sp$chinese$sp$, $sp$family$sp$, 5, $sp$Han$sp$),
  ($sp$chinese$sp$, $sp$family$sp$, 6, $sp$Jiang$sp$),
  ($sp$chinese$sp$, $sp$family$sp$, 7, $sp$Lu$sp$),
  ($sp$chinese$sp$, $sp$family$sp$, 8, $sp$Meng$sp$),
  ($sp$chinese$sp$, $sp$family$sp$, 9, $sp$Peng$sp$),
  ($sp$chinese$sp$, $sp$family$sp$, 10, $sp$Qin$sp$),
  ($sp$chinese$sp$, $sp$family$sp$, 11, $sp$Shen$sp$),
  ($sp$chinese$sp$, $sp$family$sp$, 12, $sp$Tang$sp$),
  ($sp$chinese$sp$, $sp$family$sp$, 13, $sp$Wan$sp$),
  ($sp$chinese$sp$, $sp$family$sp$, 14, $sp$Xie$sp$),
  ($sp$chinese$sp$, $sp$family$sp$, 15, $sp$Yao$sp$),
  ($sp$chinese$sp$, $sp$family$sp$, 16, $sp$Zhu$sp$)
on conflict (locale, kind, n) do update set name = excluded.name;

-- Japanese (japanese) — given
insert into sim.person_name (locale, kind, n, name) values
  ($sp$japanese$sp$, $sp$given$sp$, 1, $sp$Akiko$sp$),
  ($sp$japanese$sp$, $sp$given$sp$, 2, $sp$Ayumu$sp$),
  ($sp$japanese$sp$, $sp$given$sp$, 3, $sp$Chiyo$sp$),
  ($sp$japanese$sp$, $sp$given$sp$, 4, $sp$Daichi$sp$),
  ($sp$japanese$sp$, $sp$given$sp$, 5, $sp$Emiko$sp$),
  ($sp$japanese$sp$, $sp$given$sp$, 6, $sp$Haruka$sp$),
  ($sp$japanese$sp$, $sp$given$sp$, 7, $sp$Hideo$sp$),
  ($sp$japanese$sp$, $sp$given$sp$, 8, $sp$Ichiro$sp$),
  ($sp$japanese$sp$, $sp$given$sp$, 9, $sp$Kaori$sp$),
  ($sp$japanese$sp$, $sp$given$sp$, 10, $sp$Makoto$sp$),
  ($sp$japanese$sp$, $sp$given$sp$, 11, $sp$Naoki$sp$),
  ($sp$japanese$sp$, $sp$given$sp$, 12, $sp$Rina$sp$),
  ($sp$japanese$sp$, $sp$given$sp$, 13, $sp$Satoshi$sp$),
  ($sp$japanese$sp$, $sp$given$sp$, 14, $sp$Sayaka$sp$),
  ($sp$japanese$sp$, $sp$given$sp$, 15, $sp$Tomoko$sp$),
  ($sp$japanese$sp$, $sp$given$sp$, 16, $sp$Yuki$sp$)
on conflict (locale, kind, n) do update set name = excluded.name;

-- Japanese (japanese) — family
insert into sim.person_name (locale, kind, n, name) values
  ($sp$japanese$sp$, $sp$family$sp$, 1, $sp$Aoki$sp$),
  ($sp$japanese$sp$, $sp$family$sp$, 2, $sp$Fujimoto$sp$),
  ($sp$japanese$sp$, $sp$family$sp$, 3, $sp$Hasegawa$sp$),
  ($sp$japanese$sp$, $sp$family$sp$, 4, $sp$Ishikawa$sp$),
  ($sp$japanese$sp$, $sp$family$sp$, 5, $sp$Kobayashi$sp$),
  ($sp$japanese$sp$, $sp$family$sp$, 6, $sp$Kondo$sp$),
  ($sp$japanese$sp$, $sp$family$sp$, 7, $sp$Matsuda$sp$),
  ($sp$japanese$sp$, $sp$family$sp$, 8, $sp$Morita$sp$),
  ($sp$japanese$sp$, $sp$family$sp$, 9, $sp$Nakagawa$sp$),
  ($sp$japanese$sp$, $sp$family$sp$, 10, $sp$Okada$sp$),
  ($sp$japanese$sp$, $sp$family$sp$, 11, $sp$Saito$sp$),
  ($sp$japanese$sp$, $sp$family$sp$, 12, $sp$Sugiyama$sp$),
  ($sp$japanese$sp$, $sp$family$sp$, 13, $sp$Takahashi$sp$),
  ($sp$japanese$sp$, $sp$family$sp$, 14, $sp$Uchida$sp$),
  ($sp$japanese$sp$, $sp$family$sp$, 15, $sp$Watanabe$sp$),
  ($sp$japanese$sp$, $sp$family$sp$, 16, $sp$Yamashita$sp$)
on conflict (locale, kind, n) do update set name = excluded.name;

-- --------------------------------------------------------------------------
-- 26 bio templates. `{cuisine}` is the only placeholder the
-- generator substitutes; the validator rejects any other.
-- --------------------------------------------------------------------------
insert into sim.bio (n, template) values
  (1, $sp$Cooking mostly for one, badly, happily.$sp$),
  (2, $sp$Weeknight food. Nothing that takes longer than the rice.$sp$),
  (3, $sp$Writing down what my parents never measured.$sp$),
  (4, $sp$Baker by weekend, spreadsheet by weekday.$sp$),
  (5, $sp$I chase texture more than flavour.$sp$),
  (6, $sp$Trying to cook through one cookbook a year.$sp$),
  (7, $sp$Fermenting things my flatmates have opinions about.$sp$),
  (8, $sp$Here to read, not to post.$sp$),
  (9, $sp$Feeding four people who agree on nothing.$sp$),
  (10, $sp$Ex-restaurant. Recovering.$sp$),
  (11, $sp$Everything in one pan or it does not happen.$sp$),
  (12, $sp$Learning to cook at 41. It is going fine.$sp$),
  (13, $sp${cuisine} food, mostly, and whatever the market had.$sp$),
  (14, $sp$Archiving my grandmother's {cuisine} recipes before they are lost.$sp$),
  (15, $sp$Homesick, so I cook {cuisine} on Sundays.$sp$),
  (16, $sp$I measure nothing and regret it constantly.$sp$),
  (17, $sp$Two knives, one pan, no patience.$sp$),
  (18, $sp$Reverse-engineering the {cuisine} dishes I grew up eating.$sp$),
  (19, $sp$Saving recipes I will absolutely never cook.$sp$),
  (20, $sp$Cooking is the only part of the day nobody emails me about.$sp$),
  (21, $sp$Lunchboxes, five days a week, for the last nine years.$sp$),
  (22, $sp$A student budget and too many opinions about salt.$sp$),
  (23, $sp$Half of these are my mother's. She has approved none of them.$sp$),
  (24, $sp$Slow food, fast schedule. It mostly works.$sp$),
  (25, $sp${cuisine} classics, adjusted for a very small kitchen.$sp$),
  (26, $sp$I keep the failures in here too.$sp$)
on conflict (n) do update set template = excluded.template;

-- What the source file no longer holds leaves the table. The
-- locales go first, so the orphan check below catches their
-- names; the rest is a length trim, because every pool is
-- dense from 1 and the upserts above have already rewritten
-- every row that survived.
delete from sim.locale where code <> all (array[
  $sp$anglophone$sp$,
  $sp$french$sp$,
  $sp$italian$sp$,
  $sp$iberian$sp$,
  $sp$mexican$sp$,
  $sp$brazilian$sp$,
  $sp$nordic$sp$,
  $sp$slavic$sp$,
  $sp$greek$sp$,
  $sp$turkish$sp$,
  $sp$levantine$sp$,
  $sp$persian$sp$,
  $sp$west-african$sp$,
  $sp$ethiopian$sp$,
  $sp$south-asian$sp$,
  $sp$chinese$sp$,
  $sp$japanese$sp$
]::text[]);

delete from sim.person_name p
where not exists (select 1 from sim.locale l where l.code = p.locale)
   or p.n > (
        select case when p.kind = 'given' then l.given_count
                    else l.family_count end
        from sim.locale l where l.code = p.locale)
   or p.kind not in ('given', 'family');

delete from sim.bio where n > 26;

do $notice$ begin
  raise notice 'Name pools loaded (% locales, % names, % bios)',
  (select count(*) from sim.locale),
  (select count(*) from sim.person_name),
  (select count(*) from sim.bio);
end $notice$;

