-- UT.11 - Collegamento delle segnalazioni alle corse e allegati facoltativi
ALTER TABLE malfunction_reports ADD COLUMN IF NOT EXISTS ride_id UUID REFERENCES rides(id);
ALTER TABLE malfunction_reports ADD COLUMN IF NOT EXISTS attachment_urls TEXT;
