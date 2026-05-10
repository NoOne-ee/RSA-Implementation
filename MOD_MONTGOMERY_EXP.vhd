library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- =============================================================================
-- MOD_MONTGOMERY_EXP
--
-- Computes  Z = X^E mod M  using Montgomery left-to-right binary exponentiation
-- with one underlying MONTGOMERY_MULT core. Formerly this entity assumed
-- "operand width == exponent width == K". That does not fit plain 1024-bit RSA,
-- where the operands are 1024 bits but the exponent-port width we want for
-- testing is only 32 bits, so the generic is split:
--
--     K     : operand / modulus width (e.g. 1024)
--     K_EXP : exponent-port width     (e.g. 32)
--
-- The FSM squares K_EXP times and multiplies for every set bit of E, so total
-- Montgomery multiplications = K_EXP + popcount(E) + 2 (init + final).
-- =============================================================================

entity MOD_MONTGOMERY_EXP is
  generic(
    K     : positive := 1024;
    K_EXP : positive := 32
  );
  port(
    clk      : in  std_logic;
    rst      : in  std_logic;
    start    : in  std_logic;

    i_X      : in  unsigned(K-1     downto 0);
    i_e      : in  unsigned(K_EXP-1 downto 0);
    i_Mod    : in  unsigned(K-1     downto 0);

    o_done   : out std_logic;
    o_Z      : out unsigned(K-1 downto 0)
  );
end entity;

architecture RTL of MOD_MONTGOMERY_EXP is

  component MONTGOMERY_MULT is
    generic(K : positive);
    port(
      clk    : in  std_logic;
      rst    : in  std_logic;
      start  : in  std_logic;
      i_X    : in  unsigned(K-1 downto 0);
      i_Y    : in  unsigned(K-1 downto 0);
      i_M    : in  unsigned(K-1 downto 0);
      o_done : out std_logic;
      o_Z    : out unsigned(K-1 downto 0)
    );
  end component;

  -- State machine: produce R^2 mod M by repeated doubling, convert X and 1 to
  -- Montgomery form, run the exponentiation loop, then leave Montgomery form.
  type state_t is (IDLE,
                   PRECOMPUTE_R2,
                   INIT_Z_START, INIT_Z_WAIT,
                   INIT_S_START, INIT_S_WAIT,
                   STEP_DECIDE,
                   SQ_START,  SQ_WAIT,
                   MUL_START, MUL_WAIT,
                   FINAL_START, FINAL_WAIT,
                   DONE);
  signal STATE : state_t := IDLE;

  signal s_X, s_Mod : unsigned(K-1     downto 0) := (others => '0');
  signal s_E        : unsigned(K_EXP-1 downto 0) := (others => '0');

  -- R^2 mod M via "S := 2*S mod M" iterated 2*K times, starting from 1.
  -- Add one extra bit so that (S<<1) cannot overflow before we compare to M.
  signal s_r2      : unsigned(K   downto 0) := (others => '0');
  signal r2_result : unsigned(K-1 downto 0) := (others => '0');
  signal r2_count  : integer range 0 to 2*K := 0;

  -- Montgomery-domain registers: reg_Z = running result, reg_S = running base.
  signal reg_Z : unsigned(K-1 downto 0) := (others => '0');
  signal reg_S : unsigned(K-1 downto 0) := (others => '0');

  -- Scan exponent from MSB down. Signed because we decrement past 0 at end.
  signal bit_index : integer range -1 to K_EXP-1 := K_EXP-1;

  -- Single shared multiplier (left-to-right exp: at most one of {sq, mul}
  -- is active in any given clock, so one core is sufficient).
  signal mm_start : std_logic := '0';
  signal mm_A     : unsigned(K-1 downto 0) := (others => '0');
  signal mm_B     : unsigned(K-1 downto 0) := (others => '0');
  signal mm_Z     : unsigned(K-1 downto 0);
  signal mm_done  : std_logic;

begin

  MM : MONTGOMERY_MULT
    generic map(K => K)
    port map(
      clk    => clk,
      rst    => rst,
      start  => mm_start,
      i_X    => mm_A,
      i_Y    => mm_B,
      i_M    => s_Mod,
      o_done => mm_done,
      o_Z    => mm_Z
    );

  process(clk, rst)
    variable doubled : unsigned(K+1 downto 0);
  begin
    if rst = '1' then
      STATE     <= IDLE;
      s_X       <= (others => '0');
      s_E       <= (others => '0');
      s_Mod     <= (others => '0');
      s_r2      <= (others => '0');
      r2_result <= (others => '0');
      r2_count  <= 0;
      reg_Z     <= (others => '0');
      reg_S     <= (others => '0');
      bit_index <= K_EXP-1;
      mm_start  <= '0';
      o_Z       <= (others => '0');
      o_done    <= '0';

    elsif rising_edge(clk) then
      mm_start <= '0';
      o_done   <= '0';

      case STATE is

        when IDLE =>
          if start = '1' then
            s_X   <= i_X;
            s_E   <= i_e;
            s_Mod <= i_Mod;
            s_r2  <= to_unsigned(1, K+1);
            r2_count <= 0;
            STATE <= PRECOMPUTE_R2;
          end if;

        -- R^2 mod M = (2^(2K)) mod M  computed by doubling 1 a total of 2K times
        when PRECOMPUTE_R2 =>
          if r2_count = 2*K then
            r2_result <= resize(s_r2, K);
            STATE     <= INIT_Z_START;
          else
            doubled := ('0' & s_r2) + ('0' & s_r2);
            if doubled >= resize(s_Mod, doubled'length) then
              s_r2 <= resize(doubled - resize(s_Mod, doubled'length), K+1);
            else
              s_r2 <= resize(doubled, K+1);
            end if;
            r2_count <= r2_count + 1;
          end if;

        -- Z_bar = MonPro(1, R^2) = R mod M   (Montgomery representation of 1)
        when INIT_Z_START =>
          mm_A     <= to_unsigned(1, K);
          mm_B     <= r2_result;
          mm_start <= '1';
          STATE    <= INIT_Z_WAIT;

        when INIT_Z_WAIT =>
          if mm_done = '1' then
            reg_Z <= mm_Z;
            STATE <= INIT_S_START;
          end if;

        -- S_bar = MonPro(X, R^2) = X*R mod M
        when INIT_S_START =>
          mm_A     <= s_X;
          mm_B     <= r2_result;
          mm_start <= '1';
          STATE    <= INIT_S_WAIT;

        when INIT_S_WAIT =>
          if mm_done = '1' then
            reg_S     <= mm_Z;
            bit_index <= K_EXP-1;
            STATE     <= STEP_DECIDE;
          end if;

        -- Left-to-right square-and-multiply, MSB first.
        --   Z := MonPro(Z, Z)
        --   if bit = 1: Z := MonPro(Z, S_bar)
        when STEP_DECIDE =>
          if bit_index < 0 then
            STATE <= FINAL_START;
          else
            mm_A     <= reg_Z;
            mm_B     <= reg_Z;
            mm_start <= '1';
            STATE    <= SQ_WAIT;
          end if;

        when SQ_WAIT =>
          if mm_done = '1' then
            reg_Z <= mm_Z;
            if s_E(bit_index) = '1' then
              STATE <= MUL_START;
            else
              bit_index <= bit_index - 1;
              STATE     <= STEP_DECIDE;
            end if;
          end if;

        when MUL_START =>
          mm_A     <= mm_Z;      -- the square we just produced
          mm_B     <= reg_S;     -- base in Montgomery form
          mm_start <= '1';
          STATE    <= MUL_WAIT;

        when MUL_WAIT =>
          if mm_done = '1' then
            reg_Z     <= mm_Z;
            bit_index <= bit_index - 1;
            STATE     <= STEP_DECIDE;
          end if;

        -- Leave Montgomery domain:  Z = MonPro(Z_bar, 1)
        when FINAL_START =>
          mm_A     <= reg_Z;
          mm_B     <= to_unsigned(1, K);
          mm_start <= '1';
          STATE    <= FINAL_WAIT;

        when FINAL_WAIT =>
          if mm_done = '1' then
            o_Z   <= mm_Z;
            STATE <= DONE;
          end if;

        -- Hold o_done high until the host deasserts start.
        when DONE =>
          o_done <= '1';
          if start = '0' then
            STATE <= IDLE;
          end if;
      end case;

      -- Safety: if E == 0 the result is 1 mod M. The left-to-right loop above
      -- handles E=0 correctly (it falls straight through to FINAL, which
      -- returns MonPro(R, 1) = 1 mod M), so no special case is needed here.
    end if;
  end process;

end RTL;
