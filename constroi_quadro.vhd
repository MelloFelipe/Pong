LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE work.UC_pack.ALL;

entity constroi_quadro is
	port (
		 clock        : in std_logic;
		 current_state: in states_UC;
		 VGA_R, VGA_G, VGA_B    : out std_logic_vector(7 downto 0);
		 VGA_HS, VGA_VS         : out std_logic;
		 VGA_BLANK_N, VGA_SYNC_N: out std_logic;
		 VGA_CLK                : out std_logic
		 );
	end constroi_quadro;
	
architecture comportamento of constroi_quadro is

signal addr : integer range 0 to 12287;       -- endereco mem. vga
signal pixel : std_logic_vector(2 downto 0);  -- valor de cor do pixel
signal sync, blank: std_logic;

begin

	-- Aqui instanciamos o controlador de vídeo, 128 colunas por 96 linhas
	-- (aspect ratio 4:3). Os sinais que iremos utilizar para comunicar
	-- com a memória de vídeo (para alterar o brilho dos pixels) são
	-- write_clk (nosso clock), write_enable ('1' quando queremos escrever
	-- o valor de um pixel), write_addr (endereço do pixel a escrever)
	-- e data_in (valor do brilho do pixel RGB, 1 bit pra cada componente de cor)
	vga_controller: entity work.vgacon port map (
		 clk50M       => clock,
		 rstn         => '1',
		 red          => VGA_R,
		 green        => VGA_G,
		 blue         => VGA_B,
		 hsync        => VGA_HS,
		 vsync        => VGA_VS,
		 write_clk    => clock,
		 write_enable => 1,
		 write_addr   => addr,
		 data_in      => pixel,
		 vga_clk      => VGA_CLK,
		 sync         => sync,
		 blank        => blank);
	VGA_SYNC_N  <= NOT sync;
   VGA_BLANK_N <= NOT blank;
	 
end comportamento;