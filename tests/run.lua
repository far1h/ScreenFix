package.path = "./?.lua;./?/init.lua;" .. package.path
local test = require("tests.test_helper")
require("tests.geometry_test")
require("tests.mask_overlay_test")
require("tests.screen_config_test")
require("tests.window_guard_test")
os.exit(test.run())
