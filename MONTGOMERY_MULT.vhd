library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity MONTGOMERY_MULT is
  generic(K : positive := 32);
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
end entity;

architecture rtl of MONTGOMERY_MULT is
  type state_t is (IDLE, RUN, DONE);
  signal state : state_t := IDLE;
  signal X_reg, Y_reg, M_reg : unsigned(K-1 downto 0);
  signal S : unsigned(K+2 downto 0);   -- 2 extra bits (safe)
  signal cnt : integer range 0 to K-1;
begin
  process(clk, rst)
    variable temp : unsigned(K+2 downto 0);
  begin
    if rst = '1' then
      state <= IDLE;
      o_done <= '0';
      o_Z <= (others => '0');
    elsif rising_edge(clk) then
      o_done <= '0';
      case state is
        when IDLE =>
          if start = '1' then
            X_reg <= i_X;
            Y_reg <= i_Y;
            M_reg <= i_M;
            S <= (others => '0');
            cnt <= 0;
            state <= RUN;
          end if;
        when RUN =>
          temp := S;
          if X_reg(cnt) = '1' then
            temp := temp + Y_reg;
          end if;
          if temp(0) = '1' then
            temp := temp + M_reg;
          end if;
          S <= shift_right(temp, 1);
          if cnt = K-1 then
            state <= DONE;
          else
            cnt <= cnt + 1;
          end if;
        when DONE =>
          if S >= M_reg then
            o_Z <= resize(S - M_reg, K);
          else
            o_Z <= resize(S, K);
          end if;
          o_done <= '1';
          state <= IDLE;
      end case;
    end if;
  end process;
end rtl;
