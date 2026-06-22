-- OP.01 - Account di accesso alla dashboard web (operatore e amministrazione).
-- La registrazione pubblica (/auth/register) crea solo utenti con ruolo 'utente';
-- gli account dello staff vanno quindi inseriti a parte. Le password sono hashate
-- con bcrypt (cost 12), come in auth_usecase.
--
-- Credenziali di default (da cambiare in produzione):
--   operatore@ziply.it      / operatore123   -> ruolo 'operatore'
--   amministrazione@ziply.it / admin123       -> ruolo 'amministrazione'
INSERT INTO users (nome, cognome, email, password_hash, ruolo) VALUES
  ('Operatore', 'Ziply', 'operatore@ziply.it',
   '$2a$12$4hMAKkn0kWlmZoj0qJW6pOM/ECjRq7p.rqnEgpcD7WDUTcX0ILQm.', 'operatore'),
  ('Amministrazione', 'Comunale', 'amministrazione@ziply.it',
   '$2a$12$JH0fXuU87rOLLDD7sHyVp.DxMk6/YSSRrjKZ71cdW6jS3wep6Qk4a', 'amministrazione')
ON CONFLICT (email) DO NOTHING;
