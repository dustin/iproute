{-# LANGUAGE CPP #-}
{-# LANGUAGE FlexibleInstances #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module IPSpec where

#if __GLASGOW_HASKELL__ < 709
import Control.Applicative
#endif
import Control.Monad  (replicateM)
import Data.IP
import Data.List (intercalate)
import Data.Maybe (fromMaybe)
import Safe (readMay)
import Test.Hspec
import Test.Hspec.QuickCheck (prop)
import Test.QuickCheck

import RouteTableSpec ()

----------------------------------------------------------------
--
-- Arbitrary
--

data InvalidIPv4Str = Iv4 String deriving (Show)

instance Arbitrary InvalidIPv4Str where
    arbitrary = arbitraryIIPv4Str arbitrary 32

arbitraryIIPv4Str :: Gen IPv4 -> Int -> Gen InvalidIPv4Str
arbitraryIIPv4Str adrGen msklen = toIv4 <$> adrGen <*> lenGen
  where
    toIv4 adr len = Iv4 $ show adr ++ "/" ++ show len
    lenGen = oneof [choose (minBound, -1), choose (msklen + 1, maxBound)]

data InvalidIPv6Str = Iv6 String deriving (Show)

instance Arbitrary InvalidIPv6Str where
    arbitrary = arbitraryIIPv6Str arbitrary 128

arbitraryIIPv6Str :: Gen IPv6 -> Int -> Gen InvalidIPv6Str
arbitraryIIPv6Str adrGen msklen = toIv6 <$> adrGen <*> lenGen
  where
    toIv6 adr len = Iv6 $ show adr ++ "/" ++ show len
    lenGen = oneof [choose (minBound, -1), choose (msklen + 1, maxBound)]

data PaddedIPv4 = PaddedIPv4 [Int] [Int]

instance Show PaddedIPv4 where
  show (PaddedIPv4 pads digs) = intercalate "." $ zipWith (\p d -> replicate p '0' <> show d) pads digs

unpad :: PaddedIPv4 -> PaddedIPv4
unpad (PaddedIPv4 _ ds) = PaddedIPv4 [0, 0, 0, 0] ds

instance Arbitrary PaddedIPv4 where
  arbitrary = PaddedIPv4 <$> replicateM 4 (choose (0, 4)) <*> replicateM 4 (choose (0, 255))
  shrink (PaddedIPv4 pads digs) = (PaddedIPv4 <$> shrinkQuad pads <*> pure digs) <> (PaddedIPv4 pads <$> shrinkQuad digs)
    where
      shrinkQuad [0, 0, 0, 0] = []
      shrinkQuad xs = traverse (\d -> case d of 0 -> [0]; x -> shrink x) xs

----------------------------------------------------------------
--
-- Spec
--

spec :: Spec
spec = do
    describe "read" $ do
        prop "IPv4" to_str_ipv4
        prop "IPv6" to_str_ipv6
        prop "IPv4 failure" ipv4_fail
        prop "IPv6 failure" ipv6_fail
        prop "Padded IPv4" padded_ipv4
        it "can read even if unnecessary spaces exist" $ do
            (readMay " 127.0.0.1" :: Maybe IPv4) `shouldBe` readMay "127.0.0.1"
        it "does not read overflow IPv4 octets" $ do
            (readMay "127.0.0.18446744073709551617" :: Maybe IPv4) `shouldBe` Nothing
        it "can read even if unnecessary spaces exist" $ do
            (readMay " ::1" :: Maybe IPv4) `shouldBe` readMay "::1"
        it "does not read overflow mask lengths" $ do
            (readMay "192.168.0.1/18446744073709551648" :: Maybe (AddrRange IPv4)) `shouldBe` Nothing

to_str_ipv4 :: AddrRange IPv4 -> Bool
to_str_ipv4 a = readMay (show a) == Just a

to_str_ipv6 :: AddrRange IPv6 -> Bool
to_str_ipv6 a = readMay (show a) == Just a

ipv4_fail :: InvalidIPv4Str -> Bool
ipv4_fail (Iv4 a) = (readMay a :: Maybe (AddrRange IPv4)) == Nothing

ipv6_fail :: InvalidIPv6Str -> Bool
ipv6_fail (Iv6 a) = (readMay a :: Maybe (AddrRange IPv6)) == Nothing

padded_ipv4 :: PaddedIPv4 -> Bool
padded_ipv4 padded = fromMaybe False $ (==) <$> (readMay (show padded) :: Maybe IPv4) <*> readMay (show (unpad padded))
