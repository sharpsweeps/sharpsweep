/*
  # Swipes and Lines System

  ## 1. New Tables
  
  ### `lines`
  - `id` (uuid, primary key) - Unique identifier for each betting line
  - `game_id` (text) - External game identifier
  - `home_team` (text) - Home team name
  - `away_team` (text) - Away team name
  - `sport` (text) - Sport type (NFL, NBA, etc)
  - `sportsbook` (text) - Sportsbook name
  - `spread` (numeric) - Point spread
  - `spread_odds` (numeric) - Odds for spread bet
  - `total` (numeric) - Over/under total
  - `total_odds` (numeric) - Odds for total bet
  - `moneyline_home` (numeric) - Home team moneyline
  - `moneyline_away` (numeric) - Away team moneyline
  - `game_time` (timestamptz) - When the game starts
  - `is_active` (boolean) - Whether line is still available
  - `created_at` (timestamptz)
  - `updated_at` (timestamptz)

  ### `swipes`
  - `id` (uuid, primary key) - Unique swipe identifier
  - `user_id` (uuid, FK) - User who made the swipe
  - `line_id` (uuid, FK) - Line that was swiped
  - `direction` (text) - 'confident' or 'doubt'
  - `status` (text) - 'mybias', 'mylocks', or 'myarchives'
  - `sportsbook_cart` (text, nullable) - Sportsbook for locks cart
  - `swiped_from` (text) - Original screen where swipe occurred
  - `created_at` (timestamptz) - When swipe was made
  - `updated_at` (timestamptz)

  ### `line_snapshots`
  - `id` (uuid, primary key)
  - `line_id` (uuid, FK) - Reference to line
  - `snapshot_date` (date) - Date of snapshot
  - `home_team` (text)
  - `away_team` (text)
  - `spread` (numeric)
  - `spread_odds` (numeric)
  - `total` (numeric)
  - `total_odds` (numeric)
  - `confident_count` (integer) - Number of confident swipes at snapshot time
  - `doubt_count` (integer) - Number of doubt swipes at snapshot time
  - `created_at` (timestamptz) - Should be 3AM

  ### `community_bias`
  - `line_id` (uuid, primary key, FK) - One record per line
  - `confident_count` (integer) - Total confident swipes
  - `doubt_count` (integer) - Total doubt swipes
  - `updated_at` (timestamptz)

  ## 2. Security
  - Enable RLS on all tables
  - Users can read all lines (public data)
  - Users can only read/write their own swipes
  - Users can read community_bias after 5 swipes
  - Users can read line_snapshots after 5 swipes
*/

-- Create lines table
CREATE TABLE IF NOT EXISTS lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id text NOT NULL,
  home_team text NOT NULL,
  away_team text NOT NULL,
  sport text NOT NULL DEFAULT 'NFL',
  sportsbook text NOT NULL,
  spread numeric,
  spread_odds numeric,
  total numeric,
  total_odds numeric,
  moneyline_home numeric,
  moneyline_away numeric,
  game_time timestamptz NOT NULL,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create index on game_time for querying upcoming games
CREATE INDEX IF NOT EXISTS idx_lines_game_time ON lines(game_time);
CREATE INDEX IF NOT EXISTS idx_lines_is_active ON lines(is_active);
CREATE INDEX IF NOT EXISTS idx_lines_sport ON lines(sport);

-- Create swipes table
CREATE TABLE IF NOT EXISTS swipes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  line_id uuid NOT NULL REFERENCES lines(id) ON DELETE CASCADE,
  direction text NOT NULL CHECK (direction IN ('confident', 'doubt')),
  status text NOT NULL DEFAULT 'mybias' CHECK (status IN ('mybias', 'mylocks', 'myarchives')),
  sportsbook_cart text,
  swiped_from text NOT NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(user_id, line_id)
);

-- Create indexes for swipes
CREATE INDEX IF NOT EXISTS idx_swipes_user_id ON swipes(user_id);
CREATE INDEX IF NOT EXISTS idx_swipes_line_id ON swipes(line_id);
CREATE INDEX IF NOT EXISTS idx_swipes_status ON swipes(user_id, status);

-- Create line_snapshots table
CREATE TABLE IF NOT EXISTS line_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  line_id uuid NOT NULL REFERENCES lines(id) ON DELETE CASCADE,
  snapshot_date date NOT NULL,
  home_team text NOT NULL,
  away_team text NOT NULL,
  spread numeric,
  spread_odds numeric,
  total numeric,
  total_odds numeric,
  confident_count integer DEFAULT 0,
  doubt_count integer DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  UNIQUE(line_id, snapshot_date)
);

-- Create index for snapshots
CREATE INDEX IF NOT EXISTS idx_snapshots_line_date ON line_snapshots(line_id, snapshot_date);

-- Create community_bias table
CREATE TABLE IF NOT EXISTS community_bias (
  line_id uuid PRIMARY KEY REFERENCES lines(id) ON DELETE CASCADE,
  confident_count integer DEFAULT 0,
  doubt_count integer DEFAULT 0,
  updated_at timestamptz DEFAULT now()
);

-- Enable RLS on all tables
ALTER TABLE lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE swipes ENABLE ROW LEVEL SECURITY;
ALTER TABLE line_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE community_bias ENABLE ROW LEVEL SECURITY;

-- RLS Policies for lines (public read)
CREATE POLICY "Anyone can view active lines"
  ON lines FOR SELECT
  TO authenticated
  USING (is_active = true);

-- RLS Policies for swipes (users own their swipes)
CREATE POLICY "Users can view own swipes"
  ON swipes FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own swipes"
  ON swipes FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own swipes"
  ON swipes FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own swipes"
  ON swipes FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- RLS Policies for line_snapshots (visible after 5 swipes)
CREATE POLICY "Users with 5+ swipes can view snapshots"
  ON line_snapshots FOR SELECT
  TO authenticated
  USING (
    (SELECT COUNT(*) FROM swipes WHERE user_id = auth.uid()) >= 5
  );

-- RLS Policies for community_bias (visible after 5 swipes)
CREATE POLICY "Users with 5+ swipes can view community bias"
  ON community_bias FOR SELECT
  TO authenticated
  USING (
    (SELECT COUNT(*) FROM swipes WHERE user_id = auth.uid()) >= 5
  );

-- Function to update community_bias when swipes are inserted/updated
CREATE OR REPLACE FUNCTION update_community_bias()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO community_bias (line_id, confident_count, doubt_count, updated_at)
    VALUES (
      NEW.line_id,
      CASE WHEN NEW.direction = 'confident' THEN 1 ELSE 0 END,
      CASE WHEN NEW.direction = 'doubt' THEN 1 ELSE 0 END,
      now()
    )
    ON CONFLICT (line_id) DO UPDATE SET
      confident_count = community_bias.confident_count + CASE WHEN NEW.direction = 'confident' THEN 1 ELSE 0 END,
      doubt_count = community_bias.doubt_count + CASE WHEN NEW.direction = 'doubt' THEN 1 ELSE 0 END,
      updated_at = now();
  ELSIF TG_OP = 'UPDATE' AND OLD.direction != NEW.direction THEN
    UPDATE community_bias SET
      confident_count = confident_count + CASE WHEN NEW.direction = 'confident' THEN 1 ELSE -1 END,
      doubt_count = doubt_count + CASE WHEN NEW.direction = 'doubt' THEN 1 ELSE -1 END,
      updated_at = now()
    WHERE line_id = NEW.line_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to update community_bias
DROP TRIGGER IF EXISTS trigger_update_community_bias ON swipes;
CREATE TRIGGER trigger_update_community_bias
  AFTER INSERT OR UPDATE ON swipes
  FOR EACH ROW
  EXECUTE FUNCTION update_community_bias();

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers for updated_at
DROP TRIGGER IF EXISTS update_lines_updated_at ON lines;
CREATE TRIGGER update_lines_updated_at
  BEFORE UPDATE ON lines
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_swipes_updated_at ON swipes;
CREATE TRIGGER update_swipes_updated_at
  BEFORE UPDATE ON swipes
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();