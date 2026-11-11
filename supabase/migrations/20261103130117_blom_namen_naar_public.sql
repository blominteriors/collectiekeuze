alter table collectie.blom_namen set schema public;
alter table collectie.blom_namen_leveranciers set schema public;
drop schema collectie;
grant select on public.blom_namen, public.blom_namen_leveranciers to authenticated;