bind_socket = "*:11332";
milter = yes;
timeout = 120s;
upstream "local" { self_scan = yes; }
allow_file_and_shm_inputs = false;
