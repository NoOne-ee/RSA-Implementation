library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.RNS_PKG.all;

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

  type state_t is (IDLE, START_EXP, WAIT_EXP, START_DEC, WAIT_DEC, DONE_STATE);
  signal state : state_t := IDLE;

  type sl_array_t is array (natural range <>) of std_logic;

  signal msg_rns        : mod_array_t(0 to NUM_MODULI-1);
  signal exp_rns_out    : mod_array_t(0 to NUM_MODULI-1);
  signal decoded_result : unsigned(INT_WIDTH-1 downto 0);

  signal exp_start : std_logic := '0';
  signal exp_done  : sl_array_t(0 to NUM_MODULI-1);

  signal dec_pre_start : std_logic := '0';
  signal dec_pre_done  : std_logic;

  signal all_exp_done : std_logic;

begin

  ENC_U : entity work.RNS_ENCODER
    port map(
      i_x       => i_message,
      i_moduli  => i_moduli,
      o_RNS_OUT => msg_rns
    );

  GEN_EXP : for i in 0 to NUM_MODULI-1 generate
    EXP_U : entity work.MOD_MONTGOMERY_EXP
      generic map(
        K => MOD_WIDTH
      )
      port map(
        clk        => clk,
        rst        => rst,
        start      => exp_start,

        i_X        => msg_rns(i),
        i_e        => i_exp,
        i_Mod      => i_moduli(i),

        o_done     => exp_done(i),
        o_Z        => exp_rns_out(i)
      );
  end generate;

  DEC_U : entity work.RNS_DECODER
    port map(
      clk      => clk,
      rst      => rst,
      start    => dec_pre_start,

      i_moduli => i_moduli,
      i_rns    => exp_rns_out,

      o_done   => dec_pre_done,
      o_x      => decoded_result
    );

  process(exp_done)
    variable tmp : std_logic;
  begin
    tmp := '1';
    for i in 0 to NUM_MODULI-1 loop
      tmp := tmp and exp_done(i);
    end loop;
    all_exp_done <= tmp;
  end process;

  process(clk)
  begin
    if rising_edge(clk) then

      if rst = '1' then
        state         <= IDLE;
        exp_start     <= '0';
        dec_pre_start <= '0';
        o_done        <= '0';
        o_result      <= (others => '0');

      else
        exp_start     <= '0';
        dec_pre_start <= '0';
        o_done        <= '0';

        case state is

          when IDLE =>
            if start = '1' then
              state <= START_EXP;
            end if;

          when START_EXP =>
            exp_start <= '1';
            state     <= WAIT_EXP;

          when WAIT_EXP =>
            if all_exp_done = '1' then
              state <= START_DEC;
            end if;

          when START_DEC =>
            dec_pre_start <= '1';
            state         <= WAIT_DEC;

          when WAIT_DEC =>
            if dec_pre_done = '1' then
              state <= DONE_STATE;
            end if;

          when DONE_STATE =>
            if i_N /= 0 then
              o_result <= resize(decoded_result mod i_N, INT_WIDTH);
            else
              o_result <= decoded_result;
            end if;

            o_done <= '1';
            state  <= IDLE;

        end case;
      end if;
    end if;
  end process;

end RTL;