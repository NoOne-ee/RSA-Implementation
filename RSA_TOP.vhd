library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.RSA_PKG.all;

-- =============================================================================
-- RSA_TOP
--
-- Single top-level RSA entity. Instantiates:
--   * RSA_KEYGEN  -> generates (N, e, d) once on power-up / reset
--   * RSA         -> performs M^exp mod N via MOD_MONTGOMERY_EXP
--
-- The ONLY user-facing inputs are:
--   clk, rst, i_message, mode, start
--
-- Everything else (PRNG seed, key generation, exponent selection) is internal.
-- =============================================================================

entity RSA_TOP is
  port(
    clk        : in  std_logic;
    rst        : in  std_logic;

    -- The only user-driven inputs:
    i_message  : in  unsigned(2*PRIME_WIDTH-1 downto 0);
    mode       : in  std_logic;                          -- '0'=encrypt  '1'=decrypt
    start      : in  std_logic;                          -- pulse to run one op

    -- Status / data outputs:
    o_done     : out std_logic;                          -- 1-cycle pulse when o_result is valid
    o_result   : out unsigned(2*PRIME_WIDTH-1 downto 0);

    -- Debug (optional): generated key pair
    o_N        : out unsigned(2*PRIME_WIDTH-1 downto 0);
    o_e        : out unsigned(2*PRIME_WIDTH-1 downto 0);
    o_d        : out unsigned(2*PRIME_WIDTH-1 downto 0)
  );
end entity;

architecture RTL of RSA_TOP is

  constant KEY_WIDTH : positive := 2 * PRIME_WIDTH;

  -- Built-in PRNG seed. Any non-zero 128-bit constant is fine.
  constant C_SEED : unsigned(127 downto 0) := x"DEADBEEFCAFEBABE1234567890ABCDEF";

  -- -----------------------------------------------------------------
  -- RSA_KEYGEN interface
  -- -----------------------------------------------------------------
  signal kg_start : std_logic := '0';
  signal kg_load  : std_logic := '0';
  signal kg_done  : std_logic;
  signal kg_N     : unsigned(KEY_WIDTH-1 downto 0);
  signal kg_e     : unsigned(KEY_WIDTH-1 downto 0);
  signal kg_d     : unsigned(KEY_WIDTH-1 downto 0);
  signal kg_valid : std_logic;

  -- Latched key pair
  signal N_reg    : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');
  signal e_reg    : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');
  signal d_reg    : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');

  -- -----------------------------------------------------------------
  -- RSA core interface (all KEY_WIDTH bits wide now)
  -- -----------------------------------------------------------------
  signal rsa_start  : std_logic := '0';
  signal rsa_done   : std_logic;
  signal rsa_msg    : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');
  signal rsa_exp    : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');
  signal rsa_N      : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');
  signal rsa_result : unsigned(KEY_WIDTH-1 downto 0);

  -- Per-operation latches
  signal msg_reg  : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');
  signal mode_reg : std_logic := '0';

  -- Master FSM
  type state_t is (
    S_SEED_LOAD,
    S_KG_LAUNCH,
    S_KG_RUN,
    S_READY,
    S_PREP,
    S_LAUNCH,
    S_WAIT_RSA,
    S_DONE_OUT
  );
  signal state : state_t := S_SEED_LOAD;

begin

  -- -----------------------------------------------------------------
  -- Child instantiations
  -- -----------------------------------------------------------------
  U_KEYGEN : entity work.RSA_KEYGEN
    port map(
      clk     => clk,
      rst     => rst,
      start   => kg_start,
      seed    => C_SEED,
      load    => kg_load,
      o_done  => kg_done,
      o_N     => kg_N,
      o_e     => kg_e,
      o_d     => kg_d,
      o_valid => kg_valid
    );

  U_RSA : entity work.RSA
    port map(
      clk       => clk,
      rst       => rst,
      start     => rsa_start,
      i_message => rsa_msg,
      i_exp     => rsa_exp,
      i_N       => rsa_N,
      o_done    => rsa_done,
      o_result  => rsa_result
    );

  -- Debug outputs
  o_N <= N_reg;
  o_e <= e_reg;
  o_d <= d_reg;

  -- -----------------------------------------------------------------
  -- Master FSM
  -- -----------------------------------------------------------------
  process(clk, rst)
  begin
    if rst = '1' then
      state     <= S_SEED_LOAD;
      kg_start  <= '0';
      kg_load   <= '0';
      rsa_start <= '0';
      rsa_msg   <= (others => '0');
      rsa_exp   <= (others => '0');
      rsa_N     <= (others => '0');
      msg_reg   <= (others => '0');
      mode_reg  <= '0';
      N_reg     <= (others => '0');
      e_reg     <= (others => '0');
      d_reg     <= (others => '0');
      o_done    <= '0';
      o_result  <= (others => '0');

    elsif rising_edge(clk) then
      kg_start  <= '0';
      kg_load   <= '0';
      rsa_start <= '0';
      o_done    <= '0';

      case state is

        when S_SEED_LOAD =>
          kg_load <= '1';
          state   <= S_KG_LAUNCH;

        when S_KG_LAUNCH =>
          kg_start <= '1';
          state    <= S_KG_RUN;

        when S_KG_RUN =>
          if kg_done = '1' then
            if kg_valid = '1' then
              N_reg <= kg_N;
              e_reg <= kg_e;
              d_reg <= kg_d;
              state <= S_READY;
            else
              kg_start <= '1';
              state    <= S_KG_RUN;
            end if;
          end if;

        when S_READY =>
          if start = '1' then
            msg_reg  <= i_message;
            mode_reg <= mode;
            state    <= S_PREP;
          end if;

        when S_PREP =>
          rsa_msg <= msg_reg;
          rsa_N   <= N_reg;
          if mode_reg = '1' then
            rsa_exp <= d_reg;
          else
            rsa_exp <= e_reg;
          end if;
          state <= S_LAUNCH;

        when S_LAUNCH =>
          rsa_start <= '1';
          state     <= S_WAIT_RSA;

        when S_WAIT_RSA =>
          if rsa_done = '1' then
            o_result <= rsa_result;
            state    <= S_DONE_OUT;
          end if;

        when S_DONE_OUT =>
          o_done <= '1';
          state  <= S_READY;

      end case;
    end if;
  end process;

end RTL;
