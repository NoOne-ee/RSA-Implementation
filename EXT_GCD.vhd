-- =============================================================================
-- EXT_GCD.vhd
-- Extended Euclidean Algorithm (Binary GCD / modular inverse)
--
-- Computes: d = e^(-1) mod phi  (i.e., finds d such that e*d = 1 mod phi)
--
-- Uses the iterative extended Euclidean algorithm:
--   Given a = e, b = phi, find x such that a*x ≡ 1 (mod b)
--
-- Algorithm (iterative):
--   old_r = a, r = b
--   old_s = 1, s = 0
--   while r /= 0:
--     quotient = old_r / r
--     (old_r, r) = (r, old_r - quotient * r)
--     (old_s, s) = (s, old_s - quotient * s)
--   if old_r /= 1: no inverse exists
--   result = old_s mod b
--
-- This implementation uses a shift-and-subtract divider for the quotient
-- computation, operating one bit per clock cycle.
--
-- Interface:
--   start: pulse to begin computation
--   i_e:   the value to invert (public exponent)
--   i_phi: the modulus (Euler's totient)
--   o_d:   the modular inverse (private exponent)
--   o_done: asserted when result is ready
--   o_valid: '1' if inverse exists (gcd = 1), '0' otherwise
-- =============================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity EXT_GCD is
  generic(
    K : positive := 32  -- Bit width
  );
  port(
    clk     : in  std_logic;
    rst     : in  std_logic;
    start   : in  std_logic;
    i_e     : in  unsigned(K-1 downto 0);  -- Value to invert
    i_phi   : in  unsigned(K-1 downto 0);  -- Modulus
    o_done  : out std_logic;
    o_valid : out std_logic;               -- '1' if inverse exists
    o_d     : out unsigned(K-1 downto 0)   -- Result: e^(-1) mod phi
  );
end entity;

architecture RTL of EXT_GCD is

  -- FSM states
  type state_t is (
    IDLE,
    CHECK_ZERO,       -- Check if r = 0 (algorithm done)
    DIV_INIT,         -- Initialize division: quotient = old_r / r
    DIV_STEP,         -- Shift-and-subtract division (1 bit per clock)
    UPDATE,           -- Update (old_r, r) and (old_s, s)
    FINAL_ADJUST,     -- Make result positive (mod phi)
    DONE_ST
  );
  signal state : state_t := IDLE;

  -- Extended GCD registers (signed to handle negative intermediates)
  -- We use 2*K+1 bits for s values to avoid overflow during subtraction
  constant W : positive := 2*K + 1;

  signal old_r : unsigned(K-1 downto 0) := (others => '0');
  signal r_reg : unsigned(K-1 downto 0) := (others => '0');
  signal old_s : signed(W-1 downto 0)   := (others => '0');
  signal s_reg : signed(W-1 downto 0)   := (others => '0');

  -- Division registers
  signal div_num   : unsigned(K-1 downto 0) := (others => '0');  -- dividend
  signal div_den   : unsigned(K-1 downto 0) := (others => '0');  -- divisor
  signal div_quot  : unsigned(K-1 downto 0) := (others => '0');  -- quotient
  signal div_rem   : unsigned(K-1 downto 0) := (others => '0');  -- remainder
  signal div_bit   : integer range 0 to K   := 0;

  -- Saved modulus
  signal phi_reg : unsigned(K-1 downto 0) := (others => '0');

  -- Result
  signal result_reg : unsigned(K-1 downto 0) := (others => '0');
  signal valid_reg  : std_logic := '0';

begin

  process(clk, rst)
    variable temp_rem : unsigned(K-1 downto 0);
    variable q_times_s : signed(W-1 downto 0);
  begin
    if rst = '1' then
      state      <= IDLE;
      old_r      <= (others => '0');
      r_reg      <= (others => '0');
      old_s      <= (others => '0');
      s_reg      <= (others => '0');
      div_num    <= (others => '0');
      div_den    <= (others => '0');
      div_quot   <= (others => '0');
      div_rem    <= (others => '0');
      div_bit    <= 0;
      phi_reg    <= (others => '0');
      result_reg <= (others => '0');
      valid_reg  <= '0';
      o_done     <= '0';
      o_valid    <= '0';
      o_d        <= (others => '0');

    elsif rising_edge(clk) then
      o_done <= '0';

      case state is
        -- ================================================================
        when IDLE =>
          if start = '1' then
            old_r   <= i_e;
            r_reg   <= i_phi;
            old_s   <= to_signed(1, W);
            s_reg   <= to_signed(0, W);
            phi_reg <= i_phi;
            state   <= CHECK_ZERO;
          end if;

        -- ================================================================
        -- Check if r = 0 (done) or start next iteration
        when CHECK_ZERO =>
          if r_reg = 0 then
            -- GCD is in old_r; check if it's 1
            if old_r = to_unsigned(1, K) then
              valid_reg <= '1';
              state     <= FINAL_ADJUST;
            else
              valid_reg  <= '0';
              result_reg <= (others => '0');
              state      <= DONE_ST;
            end if;
          else
            -- Start division: old_r / r_reg
            div_num  <= old_r;
            div_den  <= r_reg;
            div_quot <= (others => '0');
            div_rem  <= (others => '0');
            div_bit  <= K - 1;
            state    <= DIV_STEP;
          end if;

        -- ================================================================
        -- Shift-and-subtract division (restoring), one bit per clock
        when DIV_STEP =>
          -- Shift remainder left, bring in next bit of dividend
          temp_rem := div_rem(K-2 downto 0) & div_num(div_bit);

          if temp_rem >= div_den then
            div_rem  <= temp_rem - div_den;
            div_quot(div_bit) <= '1';
          else
            div_rem  <= temp_rem;
            div_quot(div_bit) <= '0';
          end if;

          if div_bit = 0 then
            state <= UPDATE;
          else
            div_bit <= div_bit - 1;
          end if;

        -- ================================================================
        -- Update the EEA registers
        when UPDATE =>
          -- new_r = old_r - quotient * r  (which is the remainder from division)
          -- We already have the remainder in div_rem
          old_r <= r_reg;
          r_reg <= div_rem;

          -- new_s = old_s - quotient * s
          q_times_s := signed(resize(div_quot, W)) * s_reg;
          old_s <= s_reg;
          s_reg <= old_s - resize(q_times_s, W);

          state <= CHECK_ZERO;

        -- ================================================================
        -- Make result positive: if old_s < 0, add phi
        when FINAL_ADJUST =>
          if old_s < 0 then
            result_reg <= unsigned(resize(old_s + signed('0' & phi_reg), K));
          else
            result_reg <= unsigned(resize(old_s, K));
          end if;
          state <= DONE_ST;

        -- ================================================================
        when DONE_ST =>
          o_d     <= result_reg;
          o_valid <= valid_reg;
          o_done  <= '1';
          state   <= IDLE;

        when others =>
          state <= IDLE;

      end case;
    end if;
  end process;

end RTL;
