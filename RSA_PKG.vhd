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

  ---------------------------------------------------------------------------
  -- Width constants used by RSA_KEYGEN and RSA_TOP.
  -- (INT_WIDTH is also defined in RNS_PKG for legacy files; both values
  --  must stay in sync. We could in principle `use RNS_PKG` here, but
  --  keeping RSA_PKG self-contained avoids a circular include if RNS_PKG
  --  is removed later.)
  ---------------------------------------------------------------------------
  constant INT_WIDTH_C : positive := 1024;
  constant EXP_WIDTH_C : positive := 32;

  ---------------------------------------------------------------------------
  -- mod_inverse_fn: compute a^-1 mod m  (Extended Euclidean Algorithm).
  -- Used at ELABORATION TIME only (inside generics / constants).
  -- Both a and m must fit in a VHDL integer (>= 32 bits).
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
