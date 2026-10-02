local_addrs = "127.0.0.0/8, ::1";
upstream {
  revive_time = 10;
  resolve_min_interval = 10;
  lazy_resolve_time = 30;
}
