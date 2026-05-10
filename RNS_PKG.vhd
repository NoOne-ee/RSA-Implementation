library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package RNS_PKG is
  constant NUM_MODULI : positive := 35;   -- Number of the moduli
  constant MOD_WIDTH  : positive := 32;   -- Moduli width
  constant INT_WIDTH  : positive := 1024; -- Integer width

  subtype mod_word_t is unsigned(MOD_WIDTH-1 downto 0);
  subtype int_word_t is unsigned(INT_WIDTH-1 downto 0);

  type mod_array_t is array (natural range <>) of mod_word_t;
  type crt_array_t is array (natural range <>) of int_word_t;
  type int_array_t is array (natural range <>) of integer;
  
  constant i_moduli : mod_array_t(0 to NUM_MODULI-1):= (
    to_unsigned(1000003, MOD_WIDTH),
    to_unsigned(1000033, MOD_WIDTH),
    to_unsigned(1000037, MOD_WIDTH),
    to_unsigned(1000039, MOD_WIDTH),
    to_unsigned(1000081, MOD_WIDTH),
    to_unsigned(1000099, MOD_WIDTH),
    to_unsigned(1000117, MOD_WIDTH),
    to_unsigned(1000121, MOD_WIDTH),
    to_unsigned(1000133, MOD_WIDTH),
    to_unsigned(1000151, MOD_WIDTH),
    to_unsigned(1000159, MOD_WIDTH),
    to_unsigned(1000171, MOD_WIDTH),
    to_unsigned(1000183, MOD_WIDTH),
    to_unsigned(1000187, MOD_WIDTH),
    to_unsigned(1000193, MOD_WIDTH),
    to_unsigned(1000199, MOD_WIDTH),
    to_unsigned(1000211, MOD_WIDTH),
    to_unsigned(1000213, MOD_WIDTH),
    to_unsigned(1000231, MOD_WIDTH),
    to_unsigned(1000249, MOD_WIDTH),
    to_unsigned(1000253, MOD_WIDTH),
    to_unsigned(1000273, MOD_WIDTH),
    to_unsigned(1000289, MOD_WIDTH),
    to_unsigned(1000291, MOD_WIDTH),
    to_unsigned(1000303, MOD_WIDTH),
    to_unsigned(1000313, MOD_WIDTH),
    to_unsigned(1000333, MOD_WIDTH),
    to_unsigned(1000357, MOD_WIDTH),
    to_unsigned(1000367, MOD_WIDTH),
    to_unsigned(1000381, MOD_WIDTH),
    to_unsigned(1000393, MOD_WIDTH),
    to_unsigned(1000397, MOD_WIDTH),
    to_unsigned(1000403, MOD_WIDTH),
    to_unsigned(1000409, MOD_WIDTH),
    to_unsigned(1000423, MOD_WIDTH)
  );
  
end package;