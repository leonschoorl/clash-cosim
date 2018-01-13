{-# LANGUAGE OverloadedStrings #-}

import Data.Aeson.Encode.Pretty (encodePretty)

import Data.Aeson
import Data.List
import System.Environment
import Text.Printf
import GHC.Exts (fromList)

import qualified Data.Text as Text
import qualified Data.Text.Lazy.IO as T
import qualified Data.Text.Lazy.Encoding as T

genInstance :: Int -> IO ()
genInstance n = do

  let line1 = "instance {-# OVERLAPPING #-} (%sCoSimType r) => CoSim (%sr) where"
      line2 = "coSim' s streams %s = coSimBB%d (source s) (modname s) %s $ (coSim' s . parseInput streams) %s"
      line3 = "    {-# INLINE coSim' #-}"

      vars = map (('t':) . show) [1..n]
      constraints = concatMap (printf "CoSimType %s, ") vars :: String
      funcArgs = concatMap (++ " -> ") vars :: String

      aVars = map (('a':) . show) [1..n]
      args = intercalate " " aVars

  -- Instance *without* CoSimSettings argument
  printf line1 constraints funcArgs
  putStrLn ""
  putStr "    "
  printf line2 args n args args
  putStrLn ""
  putStrLn line3
  putStrLn ""

  -- Instance *with* CoSimSettings argument
  let line1 = "instance {-# OVERLAPPING #-} (%sCoSimType r) => CoSim (%sCoSimSettings -> r) where"
      line2 = "coSim' (source, name, _) streams %s settings = coSim' (source, name, settings) streams %s"
      line3 = "    {-# INLINE coSim' #-}"

  printf line1 constraints funcArgs
  putStrLn ""
  putStr "    "
  printf line2 args args
  putStrLn ""
  putStrLn line3
  putStrLn ""

genBBFunc n = do
  let aVars       = map (('a':) . show) [1..n]
      args        = intercalate " " aVars
      argsType    = concatMap (++ " -> ") aVars :: String
      constraints = concatMap (printf "CoSimType %s, ") aVars :: String

  --

  printf "coSimBB%d :: (%sCoSimType r) => String -> String -> %sr -> r" n constraints argsType
  putStrLn ""
  printf "coSimBB%d s m %s = id" n args
  putStrLn ""
  printf "{-# NOINLINE coSimBB%d #-}\n" n
  putStrLn ""


toBBValue
    :: String
    -- ^ name
    -> String
    -- ^ type
    -> String
    -- ^ templateD
    -> Value
toBBValue bbname type_ templateD =
  Object (fromList [("BlackBox", Object (fromList [
      ("name", String $ Text.pack bbname)
    , ("type", "")
    , ("templateD", String $ Text.pack templateD)
    ]))])

genBBjson :: Int -> Value
genBBjson n = toBBValue bbname "" templateD
    where
      bbname    = "CoSimClash.coSimBB" ++ show n
      args      = concat [printf "~ARG[%d], " i | i <- [3+n..3+2*n-1]] :: String
      template  = printf "~TEMPLATE[~LIT[%d].v][~LIT[%d]]" (n+2) (n+1)
      compname  = printf "~STRLIT[%d]" (n+2)
      instanc_  = printf "~GENSYM[~STRLIT[%d]_inst][0] (%s~RESULT)" (n+2) args
      templateD = unwords [template, compname, instanc_, ";"]


main = do
  args <- getArgs
  let n = read (head args) :: Int

  --
  putStr   "-- CoSim instances. Implemented to support up to "
  putStr   (show n)
  putStrLn " arguments."
  putStrLn "--"
  putStrLn "-- This was originally implemented similar to /printf/, to support an infinite"
  putStrLn "-- number of arguments. In order to generate blackboxes however, we need to know"
  putStrLn "-- the number of arguments at statically, hence the verbose implementation."
  putStrLn "--"
  putStrLn "-- These instances were generated by utils/coSimTemplate.hs. If we ever need to"
  putStrLn "-- support more arguments, just rerun that script."
  putStrLn "-- "
  putStrLn "-- TODO: Replace by Haskell code generation"


  putStrLn "instance {-# OVERLAPPABLE #-} CoSimType r => CoSim r where"
  putStrLn "    coSim' s streams = parseOutput (coSimStart s) streams"
  putStrLn ""

  putStrLn "instance {-# OVERLAPPABLE #-} CoSimType r => CoSim (CoSimSettings -> r) where"
  putStrLn "    coSim' (source, name, _) streams settings = coSim' (source, name, settings) streams"
  putStrLn ""

  mapM genInstance [1..n]

  --
  putStrLn "-- Cosim functions with an associated blackbox"
  mapM genBBFunc [0..n]

  --
  putStrLn "{-"
  putStrLn "Blackboxes: "
  putStrLn ""
  let blackboxes = map genBBjson [0..n]
  T.putStrLn . T.decodeUtf8 . encodePretty $ Array $ fromList blackboxes
  putStrLn ""
  putStrLn "-}"