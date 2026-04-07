import { createClient } from '@supabase/supabase-js'

const supabaseUrl = 'https://vxvflhjbafqwehuxnmeq.supabase.co'
const supabaseKey = 'sb_publishable_ZBDaQPQdFyC5kOHGbce9Ig_zdtIi6Mo'

export const supabase = createClient(supabaseUrl, supabaseKey)
