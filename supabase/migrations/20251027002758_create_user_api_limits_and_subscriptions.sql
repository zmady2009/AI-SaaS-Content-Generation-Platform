/*
  # Create User API Limits and Subscriptions Tables

  ## Overview
  This migration creates the core tables for the AI SaaS platform to manage user API usage limits and Stripe subscriptions.

  ## New Tables

  ### 1. `user_api_limits`
  Tracks API usage for each user to enforce free tier limits.
  
  **Columns:**
  - `id` (uuid, primary key) - Unique identifier for each record
  - `user_id` (text, unique, not null) - Clerk user ID
  - `count` (integer, default 0) - Number of API calls made by the user
  - `created_at` (timestamptz) - Record creation timestamp
  - `updated_at` (timestamptz) - Record last update timestamp

  ### 2. `user_subscriptions`
  Stores Stripe subscription information for pro users.
  
  **Columns:**
  - `id` (uuid, primary key) - Unique identifier for each record
  - `user_id` (text, unique, not null) - Clerk user ID
  - `stripe_customer_id` (text, unique) - Stripe customer identifier
  - `stripe_subscription_id` (text, unique) - Stripe subscription identifier
  - `stripe_price_id` (text) - Stripe price/plan identifier
  - `stripe_current_period_end` (timestamptz) - Subscription period end date
  - `created_at` (timestamptz) - Record creation timestamp
  - `updated_at` (timestamptz) - Record last update timestamp

  ## Security

  ### Row Level Security (RLS)
  - Both tables have RLS enabled by default
  - Users can only read their own data (based on user_id matching auth.uid())
  - Service role bypasses RLS for server-side operations

  ### Policies
  - `user_api_limits`: Users can view their own API limit data
  - `user_subscriptions`: Users can view their own subscription data

  ## Performance

  ### Indexes
  - Primary key indexes on `id` for both tables
  - Unique indexes on `user_id` for fast user lookups
  - Unique indexes on Stripe identifiers for webhook processing
  - Index on `stripe_current_period_end` for subscription validation queries

  ## Important Notes
  - All Stripe fields are nullable to support free tier users
  - `user_id` stores Clerk authentication user IDs
  - Timestamps use `timestamptz` for timezone awareness
  - Server-side code should use service role for all database operations
*/

-- Create user_api_limits table
CREATE TABLE IF NOT EXISTS user_api_limits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id text UNIQUE NOT NULL,
  count integer DEFAULT 0 NOT NULL,
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz DEFAULT now() NOT NULL
);

-- Create user_subscriptions table
CREATE TABLE IF NOT EXISTS user_subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id text UNIQUE NOT NULL,
  stripe_customer_id text UNIQUE,
  stripe_subscription_id text UNIQUE,
  stripe_price_id text,
  stripe_current_period_end timestamptz,
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz DEFAULT now() NOT NULL
);

-- Enable Row Level Security
ALTER TABLE user_api_limits ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_subscriptions ENABLE ROW LEVEL SECURITY;

-- Create policies for user_api_limits
-- Note: These policies are restrictive by default
-- Server-side code will use service role which bypasses RLS
CREATE POLICY "Users can view own API limits"
  ON user_api_limits
  FOR SELECT
  TO authenticated
  USING (auth.uid()::text = user_id);

-- Create policies for user_subscriptions
CREATE POLICY "Users can view own subscription"
  ON user_subscriptions
  FOR SELECT
  TO authenticated
  USING (auth.uid()::text = user_id);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_user_api_limits_user_id ON user_api_limits(user_id);
CREATE INDEX IF NOT EXISTS idx_user_subscriptions_user_id ON user_subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_user_subscriptions_stripe_customer_id ON user_subscriptions(stripe_customer_id);
CREATE INDEX IF NOT EXISTS idx_user_subscriptions_stripe_subscription_id ON user_subscriptions(stripe_subscription_id);
CREATE INDEX IF NOT EXISTS idx_user_subscriptions_period_end ON user_subscriptions(stripe_current_period_end);

-- Create function to automatically update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers to automatically update updated_at
CREATE TRIGGER update_user_api_limits_updated_at
  BEFORE UPDATE ON user_api_limits
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_user_subscriptions_updated_at
  BEFORE UPDATE ON user_subscriptions
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();
