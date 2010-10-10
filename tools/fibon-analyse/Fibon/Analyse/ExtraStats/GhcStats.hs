module Fibon.Analyse.ExtraStats.GhcStats(
    GhcStats(..)
  , parseMachineReadableStats
)
where

import Control.Monad
import Fibon.Analyse.Metrics

data GhcStats = GhcStats {
      bytesAllocated          :: Measurement MemSize
    , numGCs                  :: Measurement MemSize
    , averageBytesUsed        :: Measurement MemSize
    , maxBytesUsed            :: Measurement MemSize
    , numByteUsageSamples     :: Measurement MemSize
    , peakMegabytesAllocated  :: Measurement MemSize
    , initCPUSeconds          :: Measurement ExecTime
    , initWallSeconds         :: Measurement ExecTime
    , mutatorCPUSeconds       :: Measurement ExecTime
    , mutatorWallSeconds      :: Measurement ExecTime
    , gcCPUSeconds            :: Measurement ExecTime
    , gcWallSeconds           :: Measurement ExecTime

    -- derived metrics
    , ghcCpuTime              :: Measurement ExecTime
    , ghcWallTime             :: Measurement ExecTime
  }
  deriving (Read, Show)



parseMachineReadableStats :: String -> Maybe GhcStats
parseMachineReadableStats s = do
  stats <- toAssocList s
  let find = flip lookup stats
  bytesA <- find "bytes allocated" >>= readMem
  numG   <- find "num_GCs" >>= readMem
  avgB   <- find "average_bytes_used" >>= readMem
  maxB   <- find "max_bytes_used" >>= readMem
  numS   <- find "num_byte_usage_samples" >>= readMem
  peakA  <- find "peak_megabytes_allocated" >>= readMem
  initC  <- find "init_cpu_seconds" >>= readTime
  initW  <- find "init_wall_seconds" >>= readTime
  mutC   <- find "mutator_cpu_seconds" >>= readTime
  mutW   <- find "mutator_wall_seconds" >>= readTime
  gcC    <- find "GC_cpu_seconds" >>= readTime
  gcW    <- find "GC_wall_seconds" >>= readTime
  ghcC   <- initC `addM` mutC >>= addM gcC
  ghcW   <- initW `addM` mutW >>= addM gcW
  return GhcStats {
      bytesAllocated          = bytesA
    , numGCs                  = numG
    , averageBytesUsed        = avgB
    , maxBytesUsed            = maxB
    , numByteUsageSamples     = numS
    , peakMegabytesAllocated  = peakA
    , initCPUSeconds          = initC
    , initWallSeconds         = initW
    , mutatorCPUSeconds       = mutC
    , mutatorWallSeconds      = mutW
    , gcCPUSeconds            = gcC
    , gcWallSeconds           = gcW
    -- derived metrics
    , ghcCpuTime              = ghcC
    , ghcWallTime             = ghcW
  }

toAssocList :: String -> Maybe [(String, String)]
toAssocList = tryRead . unlines . drop 1 . lines

readMem :: String -> Maybe (Measurement MemSize)
readMem s = (Single . MemSize) `liftM` (tryRead s)

readTime :: String -> Maybe (Measurement ExecTime)
readTime s = (Single . ExecTime) `liftM` (tryRead s)

tryRead :: Read a => String -> Maybe a
tryRead s =
  case reads s of
    [(p,_)] -> Just p
    _       -> Nothing

addM :: Num a => Measurement a -> Measurement a -> Maybe (Measurement a)
addM (Single a) (Single b) = Just $ Single (a+b)
addM _ _ = Nothing

