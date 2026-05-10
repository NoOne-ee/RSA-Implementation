library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package RNS_PKG is
  constant NUM_MODULI : positive := 4;
  constant MOD_WIDTH  : positive := 32;
  constant INT_WIDTH  : positive := 1024;

  subtype mod_word_t  is unsigned(MOD_WIDTH-1 downto 0);
  type    mod_array_t is array (natural range <>) of mod_word_t;
end package;
