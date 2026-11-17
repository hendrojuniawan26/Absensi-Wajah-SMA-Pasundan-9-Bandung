-- ============================================================================
-- SKRIP SQL MIGRASI SUPABASE
-- Sistem Absensi Wajah Siswa Realtime - SMA Pasundan 9 Bandung
-- Salin seluruh skrip ini dan jalankan di Supabase Dashboard -> SQL Editor
-- ============================================================================

-- 1. Aktifkan ekstensi pgcrypto jika belum aktif (untuk gen_random_uuid)
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. Tabel Master Data Siswa (students)
CREATE TABLE IF NOT EXISTS public.students (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nisn TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  class_name TEXT NOT NULL,
  face_descriptor JSONB NOT NULL, -- Menyimpan array 128 vektor float wajah
  photo_url TEXT,                 -- Menyimpan thumbnail foto siswa (Data URL / URL)
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indeks untuk mempercepat filter berdasarkan kelas dan pencarian NISN
CREATE INDEX IF NOT EXISTS idx_students_class_name ON public.students (class_name);
CREATE INDEX IF NOT EXISTS idx_students_nisn ON public.students (nisn);

-- 3. Tabel Log Kehadiran Siswa (attendances)
CREATE TABLE IF NOT EXISTS public.attendances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  class_name TEXT NOT NULL,
  date DATE NOT NULL DEFAULT CURRENT_DATE,
  time TIME NOT NULL DEFAULT CURRENT_TIME,
  status TEXT NOT NULL DEFAULT 'Hadir',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- Mencegah absensi ganda untuk siswa yang sama pada tanggal yang sama
  CONSTRAINT attendances_student_date_unique UNIQUE (student_id, date)
);

-- Indeks untuk query kehadiran harian & filter kelas
CREATE INDEX IF NOT EXISTS idx_attendances_date_class ON public.attendances (date, class_name);

-- 4. Konfigurasi Row Level Security (RLS)
-- Aplikasi berjalan langsung di browser sekolah menggunakan Anon Key.
-- Kebijakan di bawah mengizinkan akses baca/tulis dari aplikasi SPA sekolah.
ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendances ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow public read students" ON public.students;
CREATE POLICY "Allow public read students"
  ON public.students FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "Allow public insert students" ON public.students;
CREATE POLICY "Allow public insert students"
  ON public.students FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "Allow public delete students" ON public.students;
CREATE POLICY "Allow public delete students"
  ON public.students FOR DELETE
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "Allow public read attendances" ON public.attendances;
CREATE POLICY "Allow public read attendances"
  ON public.attendances FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "Allow public insert attendances" ON public.attendances;
CREATE POLICY "Allow public insert attendances"
  ON public.attendances FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

-- 5. Aktifkan Supabase Realtime untuk tabel attendances (dan students)
-- Agar listener event INSERT di browser sekolah menerima pembaruan secara instan.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'attendances'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.attendances;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'students'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.students;
  END IF;
END $$;
