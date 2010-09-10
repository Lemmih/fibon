{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Fibon.ConfigMonad (
    FlagParameter(..)
  , FlagConfig(..)
  , Configuration
  , ConfigState(..)
  , ConfigMonad
  , done
  , append
  , replace
  , setTimeout
  , runWithInitialFlags
  , collectExtraStatsFrom
  , noExtraStats
  , useGhcDir
  , useGhcInPlaceDir
)
where

import Control.Monad.State
import qualified Data.Map as Map
import Fibon.FlagConfig
import Fibon.Timeout
import System.FilePath

data FlagParameter =
    ConfigureFlags
  | BuildFlags
  | RunFlags
  deriving (Show, Eq, Ord, Enum)

newtype GenConfigMonad a = CM {
    configState :: (State (ConfigState ConfigMap) a)
  }
  deriving (Monad)

data ConfigState a = ConfigState {
    flags          :: a
  , limit          :: Timeout
  , extraStatsFile :: Maybe FilePath
  }
type ConfigMap   = Map.Map FlagParameter [String]
type ConfigMonad = GenConfigMonad ()
type Configuration = ConfigState FlagConfig

done :: ConfigMonad
done = CM (return ())

replace :: FlagParameter -> String -> ConfigMonad
replace p f = do
  CM $ modify $ (\c -> c {flags = Map.insert p [f] (flags c)})

append :: FlagParameter -> String -> ConfigMonad
append p f = do
  CM $ modify $ (\c -> c {flags = Map.insertWith (flip (++)) p as (flags c)})
  where as = words f

setTimeout :: Timeout -> ConfigMonad
setTimeout t = do
  CM $ modify $ (\c -> c {limit = t})

collectExtraStatsFrom :: FilePath -> ConfigMonad
collectExtraStatsFrom f = do
  CM $ modify $ (\c -> c {extraStatsFile = Just f})

noExtraStats :: ConfigMonad
noExtraStats = do
  CM $ modify $ (\c -> c {extraStatsFile = Nothing})

useGhcDir :: FilePath -> ConfigMonad
useGhcDir dir = do
  append ConfigureFlags $ "--with-ghc="++(dir </> "ghc")
  append ConfigureFlags $ "--with-ghc-pkg="++(dir </> "ghc-pkg")

useGhcInPlaceDir :: FilePath -> ConfigMonad
useGhcInPlaceDir dir = do
  append ConfigureFlags $ "--with-ghc="++(dir </> "ghc-stage2")
  append ConfigureFlags $ "--with-ghc-pkg="++(dir </> "ghc-pkg")

runWithInitialFlags :: FlagConfig -> ConfigMonad -> Configuration
runWithInitialFlags fc cm = toConfig finalState
  where
  startState = ConfigState {
      flags          = fromFlagConfig fc
    , limit          = Infinity
    , extraStatsFile = Nothing
    }
  finalState = execState (configState cm) startState

toConfig :: (ConfigState ConfigMap) -> Configuration
toConfig state = state {
    flags =
      FlagConfig {
          configureFlags = Map.findWithDefault [] ConfigureFlags configMap
        , buildFlags     = Map.findWithDefault [] BuildFlags configMap
        , runFlags       = Map.findWithDefault [] RunFlags configMap
      }
  }
  where
    configMap = flags state

fromFlagConfig :: FlagConfig -> ConfigMap
fromFlagConfig fc =
    Map.insert ConfigureFlags (configureFlags fc) $
    Map.insert BuildFlags     (buildFlags     fc) $
    Map.insert RunFlags       (runFlags       fc) $
    Map.empty
