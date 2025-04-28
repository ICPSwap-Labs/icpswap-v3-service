let upstream = https://github.com/dfinity/vessel-package-set/releases/download/mo-0.6.7-20210818/package-set.dhall sha256:c4bd3b9ffaf6b48d21841545306d9f69b57e79ce3b1ac5e1f63b068ca4f89957
let Package =
    { name : Text, version : Text, repo : Text, dependencies : List Text }

let
  -- This is where you can add your own packages to the package-set
  additions =
    [
      { name = "base"
      , repo = "https://github.com/dfinity/motoko-base"
      , version = "moc-0.11.1"
      , dependencies = [] : List Text
      }
      ,{ name = "cap"
      , repo = "https://github.com/Psychedelic/cap-motoko-library"
      , version = "v1.0.4"
      , dependencies = ["base"]
      }
      ,{ dependencies = [ "base" ]
      , name = "commons"
      , repo = "git@github.com:ICPSwap-Labs/ic-commons-v2.git"
      , version = "v0.0.11"
      }
      ,{ dependencies = [] : List Text
      , name = "token-adapter"
      , repo = "git@github.com:ICPSwap-Labs/icpswap-token-adapter.git"
      , version = "v1.0.9"
      }
      ,{ dependencies = [ "base" ]
      , name = "xtended-numbers"
      , repo = "https://github.com/edjCase/motoko_numbers"
      , version = "v1.1.0"
      }
      ,{ dependencies = [ "base", "xtended-numbers" ]
      , name = "candid"
      , repo = "https://github.com/edjCase/motoko_candid"
      , version = "v1.0.2"
      }
    ]
let
  {- This is where you can override existing packages in the package-set

     For example, if you wanted to use version `v2.0.0` of the foo library:
     let overrides = [
         { name = "foo"
         , version = "v2.0.0"
         , repo = "https://github.com/bar/foo"
         , dependencies = [] : List Text
         }
     ]
  -}
  overrides =
    [] : List Package

in  upstream # additions # overrides