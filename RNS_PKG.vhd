library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- =============================================================================
-- RNS_PKG  (post-RNS rewrite)
--
-- Originally this package carried the RNS moduli, CRT arrays, etc. that the
-- old design used. After moving to a plain 1024-bit Montgomery RSA (no RNS),
-- all of that is unused, so the package is reduced to the minimum set of
-- constants and types that the existing testbench (TB_RSA) still references:
--     INT_WIDTH, MOD_WIDTH, NUM_MODULI, mod_array_t
--
-- INT_WIDTH = 1024 is the real RSA operand width.
-- MOD_WIDTH = 32   is used here only as the width of the exponent port
--                  (enough for the testbench). For production RSA private
--                  exponents this can be widened up to INT_WIDTH.
-- NUM_MODULI / mod_array_t are kept purely so the testbench's unused
-- i_moduli signal still elaborates.
-- =============================================================================

package RNS_PKG is
  constant NUM_MODULI : positive := 4;
  constant MOD_WIDTH  : positive := 32;
  constant INT_WIDTH  : positive := 1024;

  subtype mod_word_t  is unsigned(MOD_WIDTH-1 downto 0);
  type    mod_array_t is array (natural range <>) of mod_word_t;
end package;
