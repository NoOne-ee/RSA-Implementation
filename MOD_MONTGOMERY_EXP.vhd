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
        generic(
            K : positive := 8
        );
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
    
	type state_t is (
        IDLE,
		PRECOMPUTE_R2, -- Phase 0 : Compute r^2 mod mi = (2^k)^2 mod mi
        INIT_MONTG,    -- Phase 1 : launch  MM(1,r2,N) and MM(M,r2,N) in parallel
        WAIT_INIT,     -- Phase 1 : wait for both to complete
        STEP,          -- Phase 2 : launch  MM(S,S,N)  and (if ei=1) MM(C,S,N)
        WAIT_STEP,     -- Phase 2 : wait; accumulate result
        FINAL,         -- Phase 3 : launch  MM(C,1,N)  to exit Montgomery domain
        WAIT_FINAL,    -- Phase 3 : wait
        DONE
    );
	signal STATE    : state_t := IDLE;
     
	signal s_X, s_E, s_Mod, s_r_square : unsigned(k-1 downto 0) := (others => '0');
	
	signal s_r2      : unsigned(K downto 0)   := (others => '0'); -- working register (K+1 bits)
    signal r2_result : unsigned(K-1 downto 0) := (others => '0'); -- final r^2 mod M (K bits)
    signal r2_count  : integer range 0 to 2*K := 0;               -- counts 2K doubling steps
	
	signal reg_Z                       : unsigned(k-1 downto 0)   := (others => '0'); -- for the MM(1,r2,N)
	signal reg_S                       : unsigned(k-1 downto 0)   := (others => '0'); -- for the MM(M,r2,N)
	
	signal bit_index                   : integer range 0 to k := 0;
	
	--MM_CxS: used for the multiplicatin (C = Montg(C,S,M)
	signal mm_cs_start      : std_logic := '0';
	signal mm_cs_A, mm_cs_B : unsigned(k-1 downto 0) := (others => '0');
	signal mm_cs_Z          : unsigned(k-1 downto 0)   := (others => '0');
	signal mm_cs_done       : std_logic; 
	
	--MM_SxS: used for the squaring (C = Montg(S,S,M)
	signal mm_ss_start      : std_logic := '0';
	signal mm_ss_A, mm_ss_B : unsigned(k-1 downto 0) := (others => '0');
	signal mm_ss_Z          : unsigned(k-1 downto 0)   := (others => '0');
	signal mm_ss_done       : std_logic; 
	
begin
    
	--MM_CxS: The Multiplication
	MM_CxS: MONTGOMERY_MULT
	    generic map(
            K => K 
        )
        port map(
            clk    => clk,
            rst    => rst,
            start  => mm_cs_start,

            i_X    => mm_cs_A,
            i_Y    => mm_cs_B,
            i_M    => s_Mod,

            o_done => mm_cs_done,
            o_Z    => mm_cs_Z
        );
		
    --MM_SxS: The Squaring		
	MM_SxS: MONTGOMERY_MULT
	    generic map(
            K => K
        )
        port map(
            clk    => clk,
            rst    => rst,
            start  => mm_ss_start,

            i_X    => mm_ss_A,
            i_Y    => mm_ss_B,
            i_M    => s_Mod,

            o_done => mm_ss_done,
            o_Z    => mm_ss_Z
        );
		
    
	process(clk, rst)
	    variable doubled : unsigned(k downto 0);
    begin
	    if rst = '1' then
		    STATE       <= IDLE;
            s_X         <= (others => '0');
            s_E         <= (others => '0');
            s_Mod       <= (others => '0');
			s_r2        <= (others => '0');
			r2_result   <= (others => '0');
			r2_count    <= 0;
            reg_Z       <= (others => '0');
			reg_S       <= (others => '0');
            bit_index   <= 0;
			mm_cs_start <= '0';
            mm_ss_start <= '0';
			mm_cs_A     <= (others => '0');
			mm_cs_B     <= (others => '0');
			mm_ss_A     <= (others => '0');
			mm_ss_B     <= (others => '0');
			o_Z         <= (others => '0');
			o_done      <= '0';
		
		elsif rising_edge(clk) then
		
		    mm_cs_start <= '0';
			mm_ss_start <= '0';
			o_done <= '0';
			
			case STATE is
			    
			    when IDLE =>
				    if start = '1' then
					    s_X        <= i_X;
						s_E        <= i_E;
						s_Mod      <= i_Mod;
						s_r2       <= to_unsigned(1, k+1);
						r2_count   <= 0;
						STATE      <= PRECOMPUTE_R2;
					end if;
					
			    when PRECOMPUTE_R2 => 
				    if r2_count = 2*K then
                        -- done: latch result and move on
                        r2_result <= s_r2(K-1 downto 0);
                        bit_index <= 0;
                        STATE     <= INIT_MONTG;
                    else
                        -- one doubling step with modular reduction
                        doubled := shift_left(s_r2, 1);           -- 2 * s_r2, K+1 bits
                        if doubled >= ('0' & s_Mod) then          -- compare with zero-extended M
                            s_r2 <= doubled - ('0' & s_Mod);      -- reduce mod M
                        else
                            s_r2 <= doubled;
                        end if;
                        r2_count <= r2_count + 1;
                    end if;
				
				when INIT_MONTG => 
					mm_cs_A     <= to_unsigned(1, K);
			        mm_cs_B     <= r2_result;
					mm_cs_start <= '1';         -- For launching C = Montg(1, r^2, M)
					
			        mm_ss_A     <= s_X;
			        mm_ss_B     <= r2_result;       
                    mm_ss_start <= '1';         -- For launching S = Montg(X, r^2, M)
					
					STATE       <= WAIT_INIT;
					
				when WAIT_INIT =>      -- In this state, we wait until calcul is done then we assign it to the output
				    if mm_cs_done = '1' and mm_ss_done = '1' then
					    reg_Z     <= mm_cs_Z;
						reg_S     <= mm_ss_Z;
						bit_index <= 0;
                        STATE     <= STEP;
                    end if;
                
			    when STEP => 
				    if bit_index = K then 
					    STATE <= FINAL;
					else 
					    mm_cs_A     <= reg_Z;
						mm_cs_B     <= reg_S;
						mm_cs_start <= '1'; -- Launch C = Montg(C, S, M);
						
						mm_ss_A     <= reg_S;
						mm_ss_B     <= reg_S;
						mm_ss_start <= '1'; -- Launch S = Montg(S, S, M);
						
						STATE <= WAIT_STEP;
					end if;
				
				when WAIT_STEP =>
				    if mm_cs_done = '1' and mm_ss_done = '1' then
					    reg_S     <= mm_ss_Z; -- always update S 
					
					    if s_E(bit_index) = '1' then 
					        reg_Z <= mm_cs_Z;
					    end if;
					
					    bit_index <= bit_index + 1;
					    STATE     <= STEP;
					end if;
				
				when FINAL =>
				    mm_cs_A     <= reg_Z;
					mm_cs_B     <= to_unsigned(1, k);
					mm_cs_start <= '1';
					STATE       <= WAIT_FINAL;
				
				when WAIT_FINAL =>
				    if mm_cs_done = '1' then
					    reg_Z <= mm_cs_Z; -- Final result C = X^E mod M
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
