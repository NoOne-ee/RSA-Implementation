-- =============================================================================
-- EXT_GCD.vhd
-- Extended Euclidean Algorithm (modular inverse)
--
-- Computes: d = e^(-1) mod phi  (i.e., finds d such that e*d = 1 mod phi)
--
-- Uses the iterative extended Euclidean algorithm:
--   Given a = e, b = phi, find x such that a*x = 1 (mod b)
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
-- Division is done via shift-and-subtract (1 bit per clock).
-- Multiplication (quotient * s) is done via shift-and-add (1 bit per clock).
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
    CHECK_ZERO,
    DIV_STEP,
    MUL_INIT,
    MUL_STEP,
    UPDATE,
    FINAL_ADJUST,
    DONE_ST
  );
  signal state : state_t := IDLE;

  -- Extended GCD registers
  signal old_r : unsigned(K-1 downto 0) := (others => '0');
  signal r_reg : unsigned(K-1 downto 0) := (others => '0');

  -- s values are signed, range is [-phi..phi], so K+1 bits suffice
  constant SW : positive := K + 1;
  signal old_s : signed(SW-1 downto 0) := (others => '0');
  signal s_reg : signed(SW-1 downto 0) := (others => '0');

  -- Division: old_r / r_reg
  signal div_num   : unsigned(K-1 downto 0) := (others => '0');
  signal div_den   : unsigned(K-1 downto 0) := (others => '0');
  signal div_quot  : unsigned(K-1 downto 0) := (others => '0');
  signal div_rem   : unsigned(K-1 downto 0) := (others => '0');
  signal div_bit   : integer range 0 to K-1 := 0;

  -- Multiplication: quotient * s_reg (shift-and-add)
  signal mul_a     : unsigned(K-1 downto 0)  := (others => '0');  -- quotient
  signal mul_b     : signed(SW-1 downto 0)   := (others => '0');  -- s_reg
  signal mul_acc   : signed(SW+K-1 downto 0) := (others => '0');  -- accumulator
  signal mul_bit   : integer range 0 to K-1  := 0;

  -- Saved modulus
  signal phi_reg : unsigned(K-1 downto 0) := (others => '0');

  -- Result
  signal result_reg : unsigned(K-1 downto 0) := (others => '0');
  signal valid_reg  : std_logic := '0';

begin

  process(clk, rst)
    variable temp_rem : unsigned(K-1 downto 0);
    variable new_s    : signed(SW-1 downto 0);
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
      mul_a      <= (others => '0');
      mul_b      <= (others => '0');
      mul_acc    <= (others => '0');
      mul_bit    <= 0;
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
            old_s   <= to_signed(1, SW);
            s_reg   <= to_signed(0, SW);
            phi_reg <= i_phi;
            state   <= CHECK_ZERO;
          end if;

        -- ================================================================
        when CHECK_ZERO =>
          if r_reg = 0 then
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
        -- Shift-and-subtract division, one bit per clock
        when DIV_STEP =>
          temp_rem := div_rem(K-2 downto 0) & div_num(div_bit);

          if temp_rem >= div_den then
            div_rem  <= temp_rem - div_den;
            div_quot(div_bit) <= '1';
          else
            div_rem  <= temp_rem;
            div_quot(div_bit) <= '0';
          end if;

          if div_bit = 0 then
            state <= MUL_INIT;
          else
            div_bit <= div_bit - 1;
          end if;

        -- ================================================================
        -- Initialize multiplication: quotient * s_reg
        when MUL_INIT =>
          mul_a   <= div_quot;
          mul_b   <= s_reg;
          mul_acc <= (others => '0');
          mul_bit <= 0;
          state   <= MUL_STEP;

        -- ================================================================
        -- Shift-and-add signed multiplication, one bit per clock
        when MUL_STEP =>
          if mul_a(mul_bit) = '1' then
            mul_acc <= mul_acc + shift_left(resize(mul_b, SW+K), mul_bit);
          end if;

          if mul_bit = K - 1 then
            state <= UPDATE;
          else
            mul_bit <= mul_bit + 1;
          end if;

        -- ================================================================
        -- Update EEA registers
        when UPDATE =>
          old_r <= r_reg;
          r_reg <= div_rem;

          -- new_s = old_s - (quotient * s)
          new_s := resize(resize(old_s, SW+K) - mul_acc, SW);
          old_s <= s_reg;
          s_reg <= new_s;

          state <= CHECK_ZERO;

        -- ================================================================
        -- Make result positive
        when FINAL_ADJUST =>
          if old_s < 0 then
            -- Add phi to make positive
            result_reg <= unsigned(resize(old_s + signed('0' & phi_reg), K));
          else
            result_reg <= unsigned(old_s(K-1 downto 0));
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
