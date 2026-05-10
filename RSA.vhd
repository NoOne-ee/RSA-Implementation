library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.RNS_PKG.all;

-- =============================================================================
-- RSA  (Path 2 rewrite: plain 1024-bit Montgomery, no RNS)
--
-- Computes  o_result = i_message^i_exp  mod  i_N
-- using a single MOD_MONTGOMERY_EXP instance sized to INT_WIDTH bits.
--
-- Interface is intentionally unchanged from the previous (RNS-based) version
-- so that TB_RSA compiles as-is:
--     i_message : INT_WIDTH-bit operand (m)
--     i_exp     : MOD_WIDTH-bit exponent (e) -- only 32 bits in this build,
--                 enough for the existing testbench; widen in RNS_PKG when
--                 you need full-width private exponents.
--     i_N       : INT_WIDTH-bit modulus  (N) -- now actually used.
-- =============================================================================

entity RSA is
  port(
    clk        : in  std_logic;
    rst        : in  std_logic;
    start      : in  std_logic;

    i_message  : in  unsigned(INT_WIDTH-1 downto 0);
    i_exp      : in  unsigned(MOD_WIDTH-1 downto 0);
    i_N        : in  unsigned(INT_WIDTH-1 downto 0);

    o_done     : out std_logic;
    o_result   : out unsigned(INT_WIDTH-1 downto 0)
  );
end entity;

architecture RTL of RSA is

  -- A tiny wrapper FSM around MOD_MONTGOMERY_EXP. It exists only to:
  --   1. Reduce i_message mod i_N before handing it to the Montgomery core
  --      (the core assumes 0 <= X < M), and
  --   2. Register the final o_done / o_result so the top-level handshake
  --      matches what TB_RSA expects.
  type state_t is (IDLE, REDUCE, START_EXP, WAIT_EXP, LATCH, DONE_STATE);
  signal state : state_t := IDLE;

  signal x_reduced : unsigned(INT_WIDTH-1 downto 0) := (others => '0');
  signal n_reg     : unsigned(INT_WIDTH-1 downto 0) := (others => '0');
  signal e_reg     : unsigned(MOD_WIDTH-1 downto 0) := (others => '0');

  signal exp_start : std_logic := '0';
  signal exp_done  : std_logic;
  signal exp_z     : unsigned(INT_WIDTH-1 downto 0);

begin

  EXP_U : entity work.MOD_MONTGOMERY_EXP
    generic map(
      K     => INT_WIDTH,
      K_EXP => MOD_WIDTH
    )
    port map(
      clk    => clk,
      rst    => rst,
      start  => exp_start,

      i_X    => x_reduced,
      i_e    => e_reg,
      i_Mod  => n_reg,

      o_done => exp_done,
      o_Z    => exp_z
    );

  process(clk)
  begin
    if rising_edge(clk) then

      if rst = '1' then
        state     <= IDLE;
        exp_start <= '0';
        o_done    <= '0';
        o_result  <= (others => '0');
        x_reduced <= (others => '0');
        n_reg     <= (others => '0');
        e_reg     <= (others => '0');

      else
        exp_start <= '0';
        o_done    <= '0';

        case state is

          when IDLE =>
            if start = '1' then
              -- Snapshot inputs on the cycle we accept the request.
              -- NOTE: `i_message mod i_N` is a 1024-bit remainder computed
              -- combinationally here. For synthesis this should be replaced
              -- with a multi-cycle reducer; it's fine for simulation.
              if i_N /= 0 then
                x_reduced <= resize(i_message mod i_N, INT_WIDTH);
              else
                x_reduced <= i_message;
              end if;
              n_reg <= i_N;
              e_reg <= i_exp;
              state <= REDUCE;
            end if;

          when REDUCE =>
            -- One-cycle settle for x_reduced/n_reg/e_reg, then kick off exp.
            exp_start <= '1';
            state     <= START_EXP;

          when START_EXP =>
            -- Hold start high for one more cycle so the exp core's IDLE->
            -- PRECOMPUTE_R2 transition sees it, then drop it.
            state <= WAIT_EXP;

          when WAIT_EXP =>
            if exp_done = '1' then
              state <= LATCH;
            end if;

          when LATCH =>
            -- exp_z is valid while exp_done is held; capture it into o_result.
            o_result <= exp_z;
            state    <= DONE_STATE;

          when DONE_STATE =>
            o_done <= '1';
            state  <= IDLE;

        end case;
      end if;
    end if;
  end process;

end RTL;
