library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

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

  type state_t is (IDLE, PRECOMPUTE_R2,
                   INIT_Z_START, INIT_Z_WAIT,
                   INIT_S_START, INIT_S_WAIT,
                   STEP_DECIDE,
                   SQ_START, SQ_WAIT,     -- SQ_START properly used
                   MUL_START, MUL_WAIT,
                   FINAL_START, FINAL_WAIT, DONE);
  signal STATE : state_t := IDLE;

  signal s_X, s_Mod : unsigned(K-1     downto 0) := (others => '0');
  signal s_E        : unsigned(K_EXP-1 downto 0) := (others => '0');

  signal s_r2      : unsigned(K   downto 0) := (others => '0');
  signal r2_result : unsigned(K-1 downto 0) := (others => '0');
  signal r2_count  : integer range 0 to 2*K := 0;

  signal reg_Z : unsigned(K-1 downto 0) := (others => '0');
  signal reg_S : unsigned(K-1 downto 0) := (others => '0');
  -- Latch to hold squaring result before multiply step
  signal sq_result : unsigned(K-1 downto 0) := (others => '0');

  signal bit_index : integer range -1 to K_EXP-1 := K_EXP-1;

  signal mm_start : std_logic := '0';
  signal mm_A     : unsigned(K-1 downto 0) := (others => '0');
  signal mm_B     : unsigned(K-1 downto 0) := (others => '0');
  signal mm_Z     : unsigned(K-1 downto 0);
  signal mm_done  : std_logic;

begin
  MM : MONTGOMERY_MULT
    generic map(K => K)
    port map(clk, rst, mm_start, mm_A, mm_B, s_Mod, mm_done, mm_Z);

  process(clk, rst)
    variable doubled : unsigned(K+1 downto 0);
  begin
    if rst = '1' then
      STATE     <= IDLE;
      s_X       <= (others=>'0');
      s_E       <= (others=>'0');
      s_Mod     <= (others=>'0');
      s_r2      <= (others=>'0');
      r2_result <= (others=>'0');
      r2_count  <= 0;
      reg_Z     <= (others=>'0');
      reg_S     <= (others=>'0');
      sq_result <= (others=>'0');
      bit_index <= K_EXP-1;
      mm_start  <= '0';
      mm_A      <= (others=>'0');
      mm_B      <= (others=>'0');
      o_Z       <= (others=>'0');
      o_done    <= '0';

    elsif rising_edge(clk) then
      mm_start <= '0';
      o_done   <= '0';

      case STATE is
        -- ----------------------------------------------------------------
        when IDLE =>
          if start = '1' then
            s_X      <= i_X;
            s_E      <= i_e;
            s_Mod    <= i_Mod;
            s_r2     <= to_unsigned(1, K+1);
            r2_count <= 0;
            STATE    <= PRECOMPUTE_R2;
          end if;

        -- ----------------------------------------------------------------
        -- Compute R^2 mod N by repeated doubling (2K doublings gives R^2)
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

        -- ----------------------------------------------------------------
        -- Z_mont = MonMul(1, R^2) = R mod N  (Montgomery form of 1)
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

        -- ----------------------------------------------------------------
        -- S_mont = MonMul(X, R^2) = X*R mod N  (Montgomery form of X)
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

        -- ----------------------------------------------------------------
        -- Square-and-multiply loop (MSB first)
        when STEP_DECIDE =>
          if bit_index < 0 then
            STATE <= FINAL_START;
          else
            -- Launch squaring: Z = Z^2
            mm_A     <= reg_Z;
            mm_B     <= reg_Z;
            mm_start <= '1';
            STATE    <= SQ_START;     -- NEW: dedicated start state
          end if;

        -- SQ_START: multiplier has been given start pulse; now wait
        when SQ_START =>
          STATE <= SQ_WAIT;

        when SQ_WAIT =>
          if mm_done = '1' then
            reg_Z     <= mm_Z;
            sq_result <= mm_Z;        -- latch result before next mul
            if s_E(bit_index) = '1' then
              STATE <= MUL_START;
            else
              bit_index <= bit_index - 1;
              STATE     <= STEP_DECIDE;
            end if;
          end if;

        -- MUL_START: use latched sq_result (not live mm_Z) to avoid race
        when MUL_START =>
          mm_A     <= sq_result;      -- FIXED: was mm_Z (stale wire)
          mm_B     <= reg_S;
          mm_start <= '1';
          STATE    <= MUL_WAIT;

        when MUL_WAIT =>
          if mm_done = '1' then
            reg_Z     <= mm_Z;
            bit_index <= bit_index - 1;
            STATE     <= STEP_DECIDE;
          end if;

        -- ----------------------------------------------------------------
        -- Final conversion: result = MonMul(Z_mont, 1) = Z mod N
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

        when DONE =>
          o_done <= '1';
          if start = '0' then
            STATE <= IDLE;
          end if;

        when others =>
          -- Should never be reached; safely return to IDLE
          STATE    <= IDLE;
          mm_start <= '0';
          o_done   <= '0';

      end case;
    end if;
  end process;
end RTL;
