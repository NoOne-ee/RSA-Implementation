library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.RSA_PKG.all;

-- =============================================================================
-- RSA.vhd
--
-- Simple wrapper around MOD_MONTGOMERY_EXP.
-- Computes: o_result = i_message ^ i_exp  mod  i_N
--
-- All ports are KEY_WIDTH (= 2*PRIME_WIDTH) bits wide, matching the single-K
-- interface of the user's MOD_MONTGOMERY_EXP.
-- =============================================================================

entity RSA is
  port(
    clk        : in  std_logic;
    rst        : in  std_logic;
    start      : in  std_logic;

    i_message  : in  unsigned(2*PRIME_WIDTH-1 downto 0);
    i_exp      : in  unsigned(2*PRIME_WIDTH-1 downto 0);
    i_N        : in  unsigned(2*PRIME_WIDTH-1 downto 0);

    o_done     : out std_logic;
    o_result   : out unsigned(2*PRIME_WIDTH-1 downto 0)
  );
end entity;

architecture RTL of RSA is

  constant KEY_WIDTH : positive := 2 * PRIME_WIDTH;

  type state_t is (IDLE, REDUCE, START_EXP, WAIT_EXP, LATCH, DONE_STATE);
  signal state : state_t := IDLE;

  signal x_reduced : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');
  signal n_reg     : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');
  signal e_reg     : unsigned(KEY_WIDTH-1 downto 0) := (others => '0');

  signal exp_start : std_logic := '0';
  signal exp_done  : std_logic;
  signal exp_z     : unsigned(KEY_WIDTH-1 downto 0);

begin

  EXP_U : entity work.MOD_MONTGOMERY_EXP
    generic map(
      K => KEY_WIDTH
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
              if i_N /= 0 then
                x_reduced <= resize(i_message mod i_N, KEY_WIDTH);
              else
                x_reduced <= i_message;
              end if;
              n_reg <= i_N;
              e_reg <= i_exp;
              state <= REDUCE;
            end if;
          when REDUCE =>
            exp_start <= '1';
            state     <= START_EXP;
          when START_EXP =>
            state <= WAIT_EXP;
          when WAIT_EXP =>
            if exp_done = '1' then
              state <= LATCH;
            end if;
          when LATCH =>
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
