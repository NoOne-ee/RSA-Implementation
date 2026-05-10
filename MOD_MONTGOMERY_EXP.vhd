library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity MOD_MONTGOMERY_EXP is
  generic(
    K : positive := 8
  );
  port(
    clk         : in  std_logic;
    rst         : in  std_logic;
    start       : in  std_logic;

    i_X         : in  unsigned(K-1 downto 0);
    i_e         : in  unsigned(K-1 downto 0);
    i_Mod       : in  unsigned(K-1 downto 0);

    o_done      : out std_logic;
    o_Z         : out unsigned(K-1 downto 0)
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

  type state_t is (IDLE, PRECOMPUTE_R2, INIT_MONTG, WAIT_INIT,
                   STEP, WAIT_STEP, FINAL, WAIT_FINAL, DONE);
  signal STATE : state_t := IDLE;

  signal s_X, s_E, s_Mod : unsigned(K-1 downto 0) := (others => '0');

  -- R² precomputation: use extra width to avoid overflow
  signal s_r2      : unsigned(K+3 downto 0) := (others => '0');
  signal r2_result : unsigned(K-1 downto 0) := (others => '0');
  signal r2_count  : integer range 0 to 2*K := 0;

  -- Montgomery domain registers
  signal reg_Z : unsigned(K-1 downto 0) := (others => '0');
  signal reg_S : unsigned(K-1 downto 0) := (others => '0');

  signal bit_index : integer range 0 to K := 0;

  -- Multiply engine
  signal mm_cs_start : std_logic := '0';
  signal mm_cs_A     : unsigned(K-1 downto 0) := (others => '0');
  signal mm_cs_B     : unsigned(K-1 downto 0) := (others => '0');
  signal mm_cs_Z     : unsigned(K-1 downto 0);
  signal mm_cs_done  : std_logic;

  -- Square engine
  signal mm_ss_start : std_logic := '0';
  signal mm_ss_A     : unsigned(K-1 downto 0) := (others => '0');
  signal mm_ss_B     : unsigned(K-1 downto 0) := (others => '0');
  signal mm_ss_Z     : unsigned(K-1 downto 0);
  signal mm_ss_done  : std_logic;

begin

  MM_CxS : MONTGOMERY_MULT generic map(K => K)
    port map(clk, rst, mm_cs_start, mm_cs_A, mm_cs_B, s_Mod, mm_cs_done, mm_cs_Z);

  MM_SxS : MONTGOMERY_MULT generic map(K => K)
    port map(clk, rst, mm_ss_start, mm_ss_A, mm_ss_B, s_Mod, mm_ss_done, mm_ss_Z);

  process(clk, rst)
    variable doubled : unsigned(K+4 downto 0);
  begin
    if rst = '1' then
      STATE <= IDLE;
      s_X <= (others => '0'); s_E <= (others => '0'); s_Mod <= (others => '0');
      s_r2 <= (others => '0'); r2_result <= (others => '0'); r2_count <= 0;
      reg_Z <= (others => '0'); reg_S <= (others => '0'); bit_index <= 0;
      mm_cs_start <= '0'; mm_ss_start <= '0';
      o_Z <= (others => '0'); o_done <= '0';
    elsif rising_edge(clk) then
      mm_cs_start <= '0'; mm_ss_start <= '0'; o_done <= '0';

      case STATE is
        when IDLE =>
          if start = '1' then
            s_X <= i_X; s_E <= i_E; s_Mod <= i_Mod;
            s_r2 <= to_unsigned(1, K+4);
            r2_count <= 0;
            STATE <= PRECOMPUTE_R2;
          end if;

        when PRECOMPUTE_R2 =>
          if r2_count = 2*K then
            r2_result <= resize(s_r2, K);
            STATE <= INIT_MONTG;
          else
            doubled := ('0' & s_r2) + ('0' & s_r2);
            if doubled >= resize(s_Mod, doubled'length) then
              s_r2 <= resize(doubled - resize(s_Mod, doubled'length), K+4);
            else
              s_r2 <= resize(doubled, K+4);
            end if;
            r2_count <= r2_count + 1;
          end if;

        when INIT_MONTG =>
          mm_cs_A <= to_unsigned(1, K);   mm_cs_B <= r2_result;  mm_cs_start <= '1';
          mm_ss_A <= s_X;                  mm_ss_B <= r2_result;  mm_ss_start <= '1';
          STATE <= WAIT_INIT;

        when WAIT_INIT =>
          if mm_cs_done = '1' and mm_ss_done = '1' then
            reg_Z <= mm_cs_Z;  reg_S <= mm_ss_Z;
            bit_index <= 0;
            STATE <= STEP;
          end if;

        when STEP =>
          if bit_index = K then
            STATE <= FINAL;
          else
            mm_ss_A <= reg_S;   mm_ss_B <= reg_S;   mm_ss_start <= '1';
            if s_E(bit_index) = '1' then
              mm_cs_A <= reg_Z;  mm_cs_B <= reg_S;  mm_cs_start <= '1';
            end if;
            STATE <= WAIT_STEP;
          end if;

        when WAIT_STEP =>
          if mm_ss_done = '1' then
            reg_S <= mm_ss_Z;
            if s_E(bit_index) = '1' then
              if mm_cs_done = '1' then
                reg_Z <= mm_cs_Z;
                bit_index <= bit_index + 1;
                STATE <= STEP;
              end if;
            else
              bit_index <= bit_index + 1;
              STATE <= STEP;
            end if;
          end if;

        when FINAL =>
          mm_cs_A <= reg_Z;   mm_cs_B <= to_unsigned(1, K);   mm_cs_start <= '1';
          STATE <= WAIT_FINAL;

        when WAIT_FINAL =>
          if mm_cs_done = '1' then
            o_Z <= mm_cs_Z;
            STATE <= DONE;
          end if;

        when DONE =>
          o_done <= '1';
          if start = '0' then
            STATE <= IDLE;
          end if;
      end case;
    end if;
  end process;

end RTL;