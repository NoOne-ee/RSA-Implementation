library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- =============================================================================
-- RSA_PKG
--
-- Central package for the RSA_TOP wrapper.
-- Contains the mod_inverse function used at elaboration time to compute d
-- from e and phi(N).
-- =============================================================================

package RSA_PKG is

  constant NUM_MODULI : positive := 4;
  constant MOD_WIDTH  : positive := 32;
  constant INT_WIDTH  : positive := 1024;

  ---------------------------------------------------------------------------
  -- Key-generation parameters (used by RSA_TOP and RSA_KEYGEN).
  --
  -- PRIME_WIDTH   : bit-width of the two generated primes p and q.
  --                 N = p*q has width 2*PRIME_WIDTH.
  --                 Must satisfy 2*PRIME_WIDTH <= MOD_WIDTH for the current
  --                 RSA core (which uses an MOD_WIDTH-bit exponent port).
  -- NUM_WITNESSES : number of Miller-Rabin rounds used to test primality.
  --                 Higher = more confidence, slower. 4 is fine for demos.
  ---------------------------------------------------------------------------
  constant PRIME_WIDTH   : positive := 16;
  constant NUM_WITNESSES : positive := 4;

  subtype mod_word_t  is unsigned(MOD_WIDTH-1 downto 0);
  type    mod_array_t is array (natural range <>) of mod_word_t;
  
  ---------------------------------------------------------------------------
  -- mod_inverse_fn: compute a^-1 mod m  (Extended Euclidean Algorithm).
  -- Used at ELABORATION TIME only (inside generics / generate statements).
  -- Both a and m must fit in a VHDL integer (≥ 32 bits).
  ---------------------------------------------------------------------------
  function mod_inverse_fn(a : integer; m : integer) return integer;

end package;

package body RSA_PKG is

  function mod_inverse_fn(a : integer; m : integer) return integer is
    variable t     : integer := 0;
    variable new_t : integer := 1;
    variable r     : integer := m;
    variable new_r : integer := a;
    variable q     : integer;
    variable tmp   : integer;
  begin
    while new_r /= 0 loop
      q := r / new_r;

      tmp   := t - q * new_t;
      t     := new_t;
      new_t := tmp;

      tmp   := r - q * new_r;
      r     := new_r;
      new_r := tmp;
    end loop;

    if t < 0 then
      t := t + m;
    end if;
    return t;
  end function;

end package body;
