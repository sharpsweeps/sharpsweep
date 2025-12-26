/*
  # Create user profiles with swipe tracking

  1. New Tables
    - `user_profiles`
      - `id` (uuid, primary key, references auth.users)
      - `tier` (text) - User's subscription tier (FREE, PLUS, PRO, ELITE)
      - `swipes_used` (integer) - Number of swipes used in current period
      - `swipes_reset_at` (timestamptz) - When the swipe count resets
      - `created_at` (timestamptz) - Profile creation timestamp
      - `updated_at` (timestamptz) - Last update timestamp

  2. Security
    - Enable RLS on `user_profiles` table
    - Add policy for users to read their own profile
    - Add policy for users to update their own profile

  3. Notes
    - Swipe limits by tier: FREE (20), PLUS (100), PRO (500), ELITE (unlimited)
    - Swipes reset monthly (30 days from reset_at)
*/

CREATE TABLE IF NOT EXISTS user_profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  tier text NOT NULL DEFAULT 'FREE',
  swipes_used integer NOT NULL DEFAULT 0,
  swipes_reset_at timestamptz NOT NULL DEFAULT now() + interval '30 days',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own profile"
  ON user_profiles
  FOR SELECT
  TO authenticated
  USING (auth.uid() = id);

CREATE POLICY "Users can update own profile"
  ON user_profiles
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can insert own profile"
  ON user_profiles
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = id);

-- Function to automatically update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_user_profiles_updated_at
  BEFORE UPDATE ON user_profiles
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();
