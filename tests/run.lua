package.path = "./?.lua;./?/init.lua;" .. package.path
local test = require("tests.test_helper")
require("tests.geometry_test")
os.exit(test.run())
