library ieee;
use ieee.std_logic_1164.all;

entity pong is
  port (
    CLOCK_50 : in std_logic;
    PS2_DAT  : inout STD_LOGIC;
    PS2_CLK  : inout STD_LOGIC;
    HEX1 : out std_logic_vector(6 downto 0);
    HEX0 : out std_logic_vector(6 downto 0);
	 VGA_R, VGA_G, VGA_B     : out std_logic_vector(7 downto 0);
    VGA_HS, VGA_VS          : out std_logic;
    VGA_BLANK_N, VGA_SYNC_N : out std_logic;
    VGA_CLK                 : out std_logic
  );
end pong;

architecture rtl of pong is

component kbdex_ctrl is
    generic(
      clkfreq : integer
    );
    port(
      ps2_data : inout std_logic;
      ps2_clk  : inout std_logic;
      clk :	in std_logic;
      en  : in std_logic;
      resetn : in std_logic;
      lights : in std_logic_vector(2 downto 0);
      key_on : out std_logic_vector(2 downto 0);
      key_code : out std_logic_vector(47 downto 0)
    );
  end component;
  
  component UC
  port (    
    CLOCK_50 : in  std_logic;
	 pontos_PAD1, pontos_PAD2 : in integer range 0 to 7;
	 pos_bola_x : in integer range 0 to 127;
	 pos_bola_y : in integer range 0 to 95;
	 pos_PAD1, pos_PAD2 : in integer range 3 to 92;
	 key_on   : in std_logic_vector(2 downto 0);
    key_code : in std_logic_vector(47 downto 0);
	 atualiza_pos_bola_x, atualiza_pos_bola_y, atualiza_pos_PADs : out std_logic;
	 flag_inicio, we : out std_logic;
	 addr  : out integer range 0 to 12287;
	 pixel : out std_logic_vector(2 downto 0)  -- valor de cor do pixel_aux
    );
  end component;

  component estado_partida is
	  port (
		atualiza_pos_bola_x, atualiza_pos_bola_y : in std_logic;
		flag_inicio : in std_logic;
		pos_PAD1    : in integer range 3 to 92;   
      pos_PAD2    : in integer range 3 to 92;   
		pontos_PAD1, pontos_PAD2 : out integer range 0 to 7;
		pos_bola_x : out integer range 0 to 127;
		pos_bola_y : out integer range 0 to 95
		 );
	end component;
	
	component padcon is
	  port (
		atualiza_pos_PADs : in std_logic;
		key_on   : in std_logic_vector(2 downto 0);
		key_code : in std_logic_vector(47 downto 0);
		pos_PAD1, pos_PAD2 : out integer range 3 to 92
		 );
	end component;
	
  signal key_on   : std_logic_vector(2 downto 0);
  signal key_code : std_logic_vector(47 downto 0);
  signal pontos_PAD1, pontos_PAD2 : integer range 0 to 7;
  signal pos_bola_x : integer range 0 to 127;
  signal pos_bola_y : integer range 0 to 95;
  signal atualiza_pos_bola_x, atualiza_pos_bola_y, atualiza_pos_PADs : std_logic;
  signal flag_inicio, we    : std_logic;
  signal pos_PAD1, pos_PAD2 : integer range 3 to 92;
  signal addr  : integer range 0 to 12287;       -- endereco mem. vga
  signal pixel : std_logic_vector(2 downto 0);  -- valor de cor do pixel_aux
  signal sync, blank : std_logic;

begin

   -- Aqui instanciamos o controlador de vídeo, 128 colunas por 96 linhas
	-- (aspect ratio 4:3). Os sinais que iremos utilizar para comunicar
	-- com a memória de vídeo (para alterar o brilho dos pixels) são
	-- write_clk (nosso clock), write_enable ('1' quando queremos escrever
	-- o valor de um pixel), write_addr (endereço do pixel a escrever)
	-- e data_in (valor do brilho do pixel RGB, 1 bit pra cada componente de cor)
	vga_controller: entity work.vgacon port map (
		clk50M       => CLOCK_50,
		rstn         => '1',
		red          => VGA_R,
		green        => VGA_G,
		blue         => VGA_B,
		hsync        => VGA_HS,
		vsync        => VGA_VS,
		write_clk    => CLOCK_50,
		write_enable => we,
		write_addr   => addr,
		data_in      => pixel,
		vga_clk      => VGA_CLK,
		sync         => sync,
		blank        => blank);
	VGA_SYNC_N <= NOT sync;
	VGA_BLANK_N <= NOT blank;
	
	kbdex_ctrl_inst : kbdex_ctrl
		generic map (
			clkfreq => 50000
		)
		port map (
			ps2_data => PS2_DAT,
			ps2_clk => PS2_CLK,
			clk => CLOCK_50,
			en => '1',
			resetn => '1',
			lights => "000",
			key_on => key_on,
			key_code => key_code
		);

	UC_inst: UC
		port map (
			CLOCK_50 => CLOCK_50,
			pontos_PAD1 => pontos_PAD1,
			pontos_PAD2 => pontos_PAD2,
			pos_bola_x => pos_bola_x,
			pos_bola_y => pos_bola_y,
			pos_PAD1 => pos_PAD1,
			pos_PAD2 => pos_PAD2,
			key_on => key_on,
			key_code => key_code,
			atualiza_pos_bola_x => atualiza_pos_bola_x,
			atualiza_pos_bola_y => atualiza_pos_bola_y,
			flag_inicio => flag_inicio,
			we => we,
			addr => addr,
			pixel => pixel
		);

	estado_partida_inst: estado_partida
		port map (
			atualiza_pos_bola_x => atualiza_pos_bola_x,
			atualiza_pos_bola_y => atualiza_pos_bola_y,
			flag_inicio => flag_inicio,
			pos_PAD1 => pos_PAD1,
			pos_PAD2 => pos_PAD2,
			pontos_PAD1 => pontos_PAD1,
			pontos_PAD2 => pontos_PAD2, 
			pos_bola_x => pos_bola_x,
			pos_bola_y => pos_bola_y
		);

	padcon_inst: padcon
		port map (
			atualiza_pos_PADs => atualiza_pos_PADs,
			key_on => key_on,
			key_code => key_code,
			pos_PAD1=> pos_PAD1,
			pos_PAD2=> pos_PAD2
		);
		
end rtl;
