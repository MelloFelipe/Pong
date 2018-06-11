library ieee;
use ieee.std_logic_1164.all;

entity padcon is
  port (
	CLOCK_50: in  std_logic;
	atualiza_pos_PADs: in std_logic;
	PS2_DAT : inout STD_LOGIC;
   PS2_CLK : inout STD_LOGIC;
	pos_PAD1, pos_PAD2: out integer range 3 to 92
	--key_on_out: out std_logic_vector(2 downto 0);
	--key_code_out: out std_logic_vector(47 downto 0)
    );
end padcon;

architecture structure of padcon is
  
  signal key_on : std_logic_vector(2 downto 0);
  signal key_code : std_logic_vector(47 downto 0);
  signal pos_PAD1_local: integer range 3 to 92 := 47;
  signal pos_PAD2_local: integer range 3 to 92 := 47;
  
begin  -- structure
  
    kbdex_controller2: entity work.kbdex_ctrl generic map(clkfreq=>50000) port map (
      ps2_data	=> PS2_DAT,
		ps2_clk	=> PS2_CLK,
		clk		=> CLOCK_50,
		en			=> '1',
		resetn	=> '1',
		lights	=> "000",
		key_on	=> key_on,
		key_code	=> key_code);
		
   -- purpose: Este processo irá atualizar a posicao dos PAD's
  -- type   : sequential
  -- inputs : CLOCK_50
  -- outputs: pos_PAD1 e pos_PAD2
  p_atualiza_pos_PADs: process (CLOCK_50)
  begin
    if CLOCK_50'event and CLOCK_50 = '1' then  -- rising clock edge
      if atualiza_pos_PADs = '1' then
			if key_code(15 downto 0) = x"E075" or key_code(31 downto 16) = x"E075"
		   or key_code(47 downto 32) = x"E075"	then -- Up arrow pressionada
				if pos_PAD2_local > 3 then -- PAD1 nao está no limite superior
					pos_PAD2_local <= pos_PAD2_local - 1;
				end if;
			end if;
			if key_code(15 downto 0) = x"E072" or key_code(31 downto 16) = x"E072"
		   or key_code(47 downto 32) = x"E072"	then -- Down arrow pressionada
				if pos_PAD2_local < 92 then -- PAD1 nao está no limite inferior
					pos_PAD2_local <= pos_PAD2_local + 1;
				end if;
			end if;
			if key_code(15 downto 0) = x"001D" or key_code(31 downto 16) = x"001D"
		   or key_code(47 downto 32) = x"001D"	then -- tecla 'W' pressionada
				if pos_PAD1_local > 3 then -- PAD2 nao está no limite superior
					pos_PAD1_local <= pos_PAD1_local - 1;
				end if;
			end if;
			if key_code(15 downto 0) = x"001B" or key_code(31 downto 16) = x"001B"
		   or key_code(47 downto 32) = x"001B"	then -- tecla 'S' pressionada
				if pos_PAD1_local < 92 then -- PAD2 nao está no limite inferior
					pos_PAD1_local <= pos_PAD1_local + 1;
				end if;
			end if;
      end if;
	end if;
  end process p_atualiza_pos_PADs;
  
  pos_PAD1 <= pos_PAD1_local;
  pos_PAD2 <= pos_PAD2_local;
  --key_on_out <= key_on;
  --key_code_out <= key_code;
  
end structure;