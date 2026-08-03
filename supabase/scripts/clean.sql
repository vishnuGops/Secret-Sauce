-- clean.sql — clear all recipe data but keep the schema and user accounts.
-- `recipes` cascades to versions, groups, ingredients, steps, tags links,
-- shares, likes, saves, and views. Profiles (users) are preserved.

truncate table recipes restart identity cascade;
truncate table tags restart identity cascade;
truncate table recipe_suggestions restart identity cascade;
