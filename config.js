// Optional defaults for cloud sync. You can also fill these from inside the app:
// Menu ☰ → Administration → Cloud sync.
// The anon / publishable key is designed to be public: the database only accepts
// calls through the pos_push / pos_pull functions, protected by the shop password.
window.POS_CONFIG = {
  supabaseUrl: "",   // e.g. "https://abcd1234.supabase.co"
  supabaseKey: ""    // anon key (eyJ...) or publishable key (sb_publishable_...)
};
