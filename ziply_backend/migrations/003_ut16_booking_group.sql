-- UT.16 Prenotazione multipla — raggruppa le prenotazioni e le corse create
-- insieme sotto un identificativo di gruppo condiviso. group_id NULL indica una
-- prenotazione/corsa singola (comportamento invariato di Sprint 1).
--
-- NB: se sul server il numero 003 è già occupato (es. da un align una-tantum),
-- rinumera questo file in 004 prima di applicarlo.

ALTER TABLE bookings ADD COLUMN IF NOT EXISTS group_id UUID;
ALTER TABLE rides    ADD COLUMN IF NOT EXISTS group_id UUID;
