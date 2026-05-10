-- =============================================================================
-- RANDOM_GEN.vhd
-- LFSR-based Pseudo-Random Number Generator for RSA prime candidates
-- Produces WIDTH-bit random numbers with MSB=1 and LSB=1 (odd, full-length)
--
-- Uses a 128-bit Galois LFSR with maximal-length feedback polynomial:
--   x^128 + x^126 + x^101 + x^99 + 1
--
-- Supports any WIDTH (including < 128).
-- On 'start' pulse, a new random number is generated in a few cycles.
-- =============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity RANDOM_GEN is
  generic(
    WIDTH : positive := 512  -- Output width (prime candidate size)
  );
  port(
    clk    : in  std_logic;
    rst    : in  std_logic;
    seed   : in  unsigned(127 downto 0);  -- Initial seed (must be non-zero)
    load   : in  std_logic;               -- Load seed pulse
    start  : in  std_logic;               -- Request new random number
    o_done : out std_logic;               -- Output valid
    o_rng  : out unsigned(WIDTH-1 downto 0)  -- Random output
  );
end entity;

architecture RTL of RANDOM_GEN is

  -- Number of LFSR steps needed to fill WIDTH bits
  -- Each step produces WIDTH bits (we take the lower WIDTH bits of the LFSR)
  -- For WIDTH <= 128: 1 step suffices
  -- For WIDTH > 128: we need ceil(WIDTH/128) steps
  constant NUM_STEPS : positive := (WIDTH + 127) / 128;

  type state_t is (IDLE, STEP, FINALIZE, DONE_ST);
  signal state : state_t := IDLE;

  -- 128-bit Galois LFSR state
  signal lfsr : unsigned(127 downto 0) := (others => '0');

  -- Accumulator for building the output (uses shift register approach)
  signal accum : unsigned(WIDTH-1 downto 0) := (others => '0');

  -- Step counter
  signal step_cnt : integer range 0 to NUM_STEPS-1 := 0;

  -- Function: one step of the Galois LFSR
  -- Feedback polynomial: x^128 + x^126 + x^101 + x^99 + 1
  function lfsr_step(s : unsigned(127 downto 0)) return unsigned is
    variable nxt : unsigned(127 downto 0);
    variable fb  : std_logic;
  begin
    fb := s(0);  -- feedback bit (LSB)
    nxt := '0' & s(127 downto 1);  -- shift right
    if fb = '1' then
      nxt(127) := nxt(127) xor '1';  -- x^128 (tap at bit 127)
      nxt(125) := nxt(125) xor '1';  -- x^126 (tap at bit 125)
      nxt(100) := nxt(100) xor '1';  -- x^101 (tap at bit 100)
      nxt(98)  := nxt(98)  xor '1';  -- x^99  (tap at bit 98)
    end if;
    return nxt;
  end function;

begin

  process(clk, rst)
    variable bits_remaining : integer;
    variable bits_this_step : integer;
    variable offset         : integer;
  begin
    if rst = '1' then
      state    <= IDLE;
      lfsr     <= (others => '0');
      accum    <= (others => '0');
      step_cnt <= 0;
      o_done   <= '0';
      o_rng    <= (others => '0');

    elsif rising_edge(clk) then
      o_done <= '0';

      -- Seed loading (can happen at any time, takes priority)
      if load = '1' then
        lfsr <= seed;
      end if;

      case state is
        -- ----------------------------------------------------------------
        when IDLE =>
          if start = '1' and load = '0' then
            accum    <= (others => '0');
            step_cnt <= 0;
            state    <= STEP;
          end if;

        -- ----------------------------------------------------------------
        -- Each cycle: advance LFSR and shift bits into the accumulator
        when STEP =>
          lfsr <= lfsr_step(lfsr);

          -- Calculate how many bits to take this step
          offset := step_cnt * 128;
          bits_remaining := WIDTH - offset;
          if bits_remaining >= 128 then
            bits_this_step := 128;
          else
            bits_this_step := bits_remaining;
          end if;

          -- Copy bits_this_step bits from lfsr into accum
          for i in 0 to 127 loop
            if i < bits_this_step then
              accum(offset + i) <= lfsr(i);
            end if;
          end loop;

          if step_cnt = NUM_STEPS - 1 then
            state <= FINALIZE;
          else
            step_cnt <= step_cnt + 1;
          end if;

        -- ----------------------------------------------------------------
        -- Force MSB=1 (full bit-length) and LSB=1 (odd number)
        when FINALIZE =>
          accum(WIDTH-1) <= '1';  -- MSB = 1
          accum(0)       <= '1';  -- LSB = 1 (odd)
          state          <= DONE_ST;

        -- ----------------------------------------------------------------
        when DONE_ST =>
          o_rng  <= accum;
          o_done <= '1';
          state  <= IDLE;

      end case;
    end if;
  end process;

end RTL;
