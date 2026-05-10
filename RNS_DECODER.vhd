library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.RNS_PKG.all;

entity RNS_DECODER is
  port(
    clk      : in  std_logic;
    rst      : in  std_logic;

    start    : in  std_logic;

    i_moduli : in  mod_array_t(0 to NUM_MODULI-1);
    i_rns    : in  mod_array_t(0 to NUM_MODULI-1);

    o_done   : out std_logic;
    o_x      : out unsigned(INT_WIDTH-1 downto 0)
  );
end entity;

architecture RTL of RNS_DECODER is

  signal s_M : unsigned(INT_WIDTH-1 downto 0);
  signal s_K : crt_array_t(0 to NUM_MODULI-1);

begin

  PRE_U : entity work.CRT_PRECOMPUTE
    port map(
      clk      => clk,
      rst      => rst,
      start    => start,
      i_moduli => i_moduli,
      o_done   => o_done,
      o_M      => s_M,
      o_K      => s_K
    );

  DEC_U : entity work.RNS_DECODER_FAST
    port map(
      i_rns => i_rns,
      i_K   => s_K,
      i_M   => s_M,
      o_x   => o_x
    );

end RTL;