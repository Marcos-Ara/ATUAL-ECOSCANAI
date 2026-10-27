-- Corrections stay useful even when the user reports an error without an image.
-- Training submissions still require an image and explicit consent.
alter table public.correcoes_usuario
  alter column caminho_imagem drop not null;

notify pgrst, 'reload schema';
