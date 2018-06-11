library ieee;
use ieee.std_logic_1164.all;

entity UC is
  port (    
    CLOCK_50                  : in  std_logic;
	 PS2_DAT : inout STD_LOGIC;
    PS2_CLK : inout STD_LOGIC;
    VGA_R, VGA_G, VGA_B       : out std_logic_vector(7 downto 0);
    VGA_HS, VGA_VS            : out std_logic;
    VGA_BLANK_N, VGA_SYNC_N   : out std_logic;
    VGA_CLK                   : out std_logic
    );
end UC;

architecture comportamento of UC is

	component estado_partida is
	  port (
		atualiza_pos_bola_x, atualiza_pos_bola_y: in std_logic;
		flag_inicio: in std_logic;
		pos_PAD1 : in integer range 3 to 92;   
      pos_PAD2 : in integer range 3 to 92;   
		pontos_PAD1, pontos_PAD2: out integer range 0 to 7;
		pos_bola_x: out integer range 0 to 127;
		pos_bola_y: out integer range 0 to 95
		 );
	end component;
	
	component padcon is
	  port (
		CLOCK_50: in  std_logic;
		atualiza_pos_PADs: in std_logic;
		PS2_DAT : inout STD_LOGIC;
		PS2_CLK : inout STD_LOGIC;
		pos_PAD1, pos_PAD2: out integer range 3 to 92
		 );
	end component;

  signal pos_bola_x : integer range 0 to 127:= 64;  -- coluna atual da bola
  signal pos_bola_y : integer range 0 to 95 := 47;  -- linha atual da bola
  
  signal pontos_PAD1 : integer range 0 to 7:= 0;   -- pontos marcados pelo PAD1
  signal pontos_PAD2 : integer range 0 to 7:= 0;   -- pontos marcados pelo PAD2	
	
  -- Interface com a memória de vídeo do controlador

  signal we : std_logic;                        -- write enable ('1' p/ escrita)
  signal addr : integer range 0 to 12287;       -- endereco mem. vga
  signal pixel : std_logic_vector(2 downto 0);  -- valor de cor do pixel
  signal pixel_bit : std_logic;                 -- um bit do vetor acima

  -- Sinais dos contadores de linhas e colunas utilizados para percorrer
  -- as posições da memória de vídeo (pixels) no momento de construir um quadro.
  
  signal line : integer range 0 to 95;  -- linha atual
  signal col : integer range 0 to 127;  -- coluna atual

  signal col_rstn : std_logic;          -- reset do contador de colunas
  signal col_enable : std_logic;        -- enable do contador de colunas

  signal line_rstn : std_logic;          -- reset do contador de linhas
  signal line_enable : std_logic;        -- enable do contador de linhas

  signal fim_escrita : std_logic;       -- '1' quando um quadro terminou de ser
                                        -- escrito na memória de vídeo

  -- Sinais que armazem a posição de uma bola, que deverá ser desenhada
  -- na tela de acordo com sua posição.

  signal atualiza_pos_bola_x : std_logic;    -- se '1' = bola muda sua pos. no eixo x
  signal atualiza_pos_bola_y : std_logic;    -- se '1' = bola muda sua pos. no eixo y
  
  -- Especificação dos tipos e sinais da máquina de estados de controle
  type estado_t is (inicio_jogo, inicio_partida, constroi_quadro, move_bola_e_PADs, game_over);
  signal estado: estado_t := inicio_jogo;
  signal proximo_estado: estado_t := inicio_jogo;

  -- Sinais para um contador utilizado para atrasar a atualização da
  -- posição da bola, a fim de evitar que a animação fique excessivamente
  -- veloz. Aqui utilizamos um contador de 0 a 1250000, de modo que quando
  -- alimentado com um clock de 50MHz, ele demore 25ms (40fps) para contar até o final.
  
  signal contador : integer range 0 to 1250000 - 1 := 0;  -- contador
  signal timer : std_logic;        -- vale '1' quando o contador chegar ao fim
  signal timer_rstn, timer_enable : std_logic;
  
  signal sync, blank: std_logic;

  -- Sinais para controlar o movimento dos PAD's
  -- PAD tem o seu tamanho definido como 7 pixels
  signal pos_PAD1 : integer range 3 to 92 := 47;   -- linha atual do pixel central do PAD1
  signal pos_PAD2 : integer range 3 to 92 := 47;   -- linha atual do pixel central do PAD2

  signal atualiza_pos_PADs : std_logic;    -- se '1' = PAD1 e PAD2 muda sua pos. no eixo y
  
  signal flag_inicio, flag_fim : std_logic := '0'; -- verifica se o jogo foi iniciado
  signal flag_inicio_rstn: std_logic := '1'; -- reseta valor da flag, ativo em baixo
  
  type matrix_pequena is array(4 downto 0, 4 downto 0) of std_logic;
  signal display_placar1, display_placar2 : matrix_pequena;
  type matrix_grande is array(4 downto 0, 46 downto 0) of std_logic;
  signal display_mensagem : matrix_grande;
  signal key_on : std_logic_vector(2 downto 0);
  signal key_code : std_logic_vector(47 downto 0);
  
  -- POSSIVEIS COMPLEMENTOS
  -- Permitir uma tecla que pause o jogo
  -- Permitir ao usuario selecionar a cor da interface
  
begin  -- comportamento


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

	-- controlador do teclado
	kbdex_controller: entity work.kbdex_ctrl generic map(clkfreq=>50000) port map (
		ps2_data	=> PS2_DAT,
		ps2_clk	=> PS2_CLK,
		clk		=> CLOCK_50,
		en			=> '1',
		resetn	=> '1',
		lights	=> "000",
		key_on	=> key_on,
		key_code	=> key_code);
	
	-- controlador da bola e dos pontos
	estado_partida_inst: estado_partida port map (
		atualiza_pos_bola_x => atualiza_pos_bola_x,
		atualiza_pos_bola_y => atualiza_pos_bola_y,
		flag_inicio => flag_inicio,
		pos_PAD1 => pos_PAD1,   
		pos_PAD2 => pos_PAD2,   
		pontos_PAD1 => pontos_PAD1,
		pontos_PAD2 => pontos_PAD2,
		pos_bola_x => pos_bola_x,
		pos_bola_y  => pos_bola_y
	);
	
	-- controlador dos PAD's
	padcon_inst: padcon port map (
		CLOCK_50 => CLOCK_50,
		atualiza_pos_PADs => atualiza_pos_PADs,
		PS2_DAT => PS2_DAT,
		PS2_CLK => PS2_CLK,
		pos_PAD1 => pos_PAD1,
		pos_PAD2 => pos_PAD2
	);
	
  -----------------------------------------------------------------------------
  -- Processos que controlam contadores de linhas e coluna para varrer
  -- todos os endereços da memória de vídeo, no momento de construir um quadro.
  -----------------------------------------------------------------------------
  
  -- purpose: Este processo conta o número da coluna atual, quando habilitado
  --          pelo sinal "col_enable".
  -- type   : sequential
  -- inputs : CLOCK_50, col_rstn
  -- outputs: col
  conta_coluna: process (CLOCK_50, col_rstn)
  begin  -- process conta_coluna
    if col_rstn = '0' then                  -- asynchronous reset (active low)
      col <= 0;
    elsif CLOCK_50'event and CLOCK_50 = '1' then  -- rising clock edge
      if col_enable = '1' then
        if col = 127 then               -- conta de 0 a 127 (128 colunas)
          col <= 0;
        else
          col <= col + 1;  
        end if;
      end if;
    end if;
  end process conta_coluna;
    
  -- purpose: Este processo conta o número da linha atual, quando habilitado
  --          pelo sinal "line_enable".
  -- type   : sequential
  -- inputs : CLOCK_50, line_rstn
  -- outputs: line
  conta_linha: process (CLOCK_50, line_rstn)
  begin  -- process conta_linha
    if line_rstn = '0' then                  -- asynchronous reset (active low)
      line <= 0;
    elsif CLOCK_50'event and CLOCK_50 = '1' then  -- rising clock edge
      -- o continicio_jogoador de linha só incrementa quando o contador de colunas
      -- chegou ao fim (valor 127)
      if line_enable = '1' and col = 127 then
        if line = 95 then               -- conta de 0 a 95 (96 linhas)
          line <= 0;
        else
          line <= line + 1;  
        end if;        
      end if;
    end if;
  end process conta_linha;

  -- Este sinal é útil para informar nossa lógica de controle quando
  -- o quadro terminou de ser escrito na memória de vídeo, para que
  -- possamos avançar para o próximo estado.
  fim_escrita <= '1' when (line = 95) and (col = 127)
                 else '0'; 
				 
  -----------------------------------------------------------------------------
  -- Processo que verifica se o jogo deve ser iniciado ou finalizado
  verifica_inicio_fim: process(CLOCK_50, flag_inicio_rstn)
  begin
   if flag_inicio_rstn = '0' then
			flag_inicio <= '0';
	elsif CLOCK_50'event and CLOCK_50 = '1' then
		if (pontos_PAD1 >= 7) or (pontos_PAD2 >= 7) then -- se o jogo tiver acabado
			flag_fim <= '1';
		end if;
		if key_code(15 downto 0) = x"005A" or key_code(15 downto 0) = x"E05A" then -- se a tecla "ENTER" for pressionada
			flag_inicio <= '1';
			flag_fim <= '0';
		end if;
	end if;
  end process verifica_inicio_fim;
  
   -----------------------------------------------------------------------------
  -- Mensagens
  -----------------------------------------------------------------------------
  -- Marca pixels que serao usados para imprimir o placar e as mensagens inicial
  -- e final.

	-- Para o display do placar, uma matriz 5x5 eh o suficiente para mostrar os 8 primeiros algarismos na tela
	-- (0,0) (0,1) (0,2) (0,3) (0,4) (0,5)
	-- (1,0) (1,1) (1,2) (1,3) (1,4) (1,5)
	-- (2,0) (2,1) (2,2) (2,3) (2,4) (2,5)
	-- (3,0) (3,1) (3,2) (3,3) (3,4) (3,5)
	-- (4,0) (4,1) (4,2) (4,3) (4,4) (4,5)
	-- (5,0) (5,1) (5,2) (5,3) (5,4) (5,5)

	process(CLOCK_50)
	begin
		if pontos_PAD1 = 0 then
			       display_placar1(0,0) <= '0';-- preto
					 display_placar1(0,1) <= '1';-- branco
					 display_placar1(0,2) <= '1';
					 display_placar1(0,3) <= '1';
					 display_placar1(0,4) <= '0';
					 display_placar1(1,0) <= '1';
					 display_placar1(1,1) <= '0';
					 display_placar1(1,2) <= '0';
					 display_placar1(1,3) <= '0';
					 display_placar1(1,4) <= '1';
					 display_placar1(2,0) <= '1';
					 display_placar1(2,1) <= '0';
					 display_placar1(2,2) <= '0';
					 display_placar1(2,3) <= '0';
					 display_placar1(2,4) <= '1';
					 display_placar1(3,0) <= '1';
					 display_placar1(3,1) <= '0';
					 display_placar1(3,2) <= '0';
					 display_placar1(3,3) <= '0';
					 display_placar1(3,4) <= '1';				 
					 display_placar1(4,0) <= '0';
					 display_placar1(4,1) <= '1';
					 display_placar1(4,2) <= '1';
					 display_placar1(4,3) <= '1';
					 display_placar1(4,4) <= '0';
		
		elsif pontos_PAD1 = 1 then
			       display_placar1(0,0) <= '0';
					 display_placar1(0,1) <= '0';
					 display_placar1(0,2) <= '1';
					 display_placar1(0,3) <= '1';
					 display_placar1(0,4) <= '0';
					 
					 display_placar1(1,0) <= '0';
					 display_placar1(1,1) <= '0';
					 display_placar1(1,2) <= '0';
					 display_placar1(1,3) <= '1';
					 display_placar1(1,4) <= '0';
					 
					 display_placar1(2,0) <= '0';
					 display_placar1(2,1) <= '0';
					 display_placar1(2,2) <= '0';
					 display_placar1(2,3) <= '1';
					 display_placar1(2,4) <= '0';
					 
					 display_placar1(3,0) <= '0';
					 display_placar1(3,1) <= '0';
					 display_placar1(3,2) <= '0';
					 display_placar1(3,3) <= '1';
					 display_placar1(3,4) <= '0';
					 
					 display_placar1(4,0) <= '0';
					 display_placar1(4,1) <= '0';
					 display_placar1(4,2) <= '0';
					 display_placar1(4,3) <= '1';
					 display_placar1(4,4) <= '0';
		
		elsif pontos_PAD1 = 2 then
			       display_placar1(0,0) <= '1';
					 display_placar1(0,1) <= '1';
					 display_placar1(0,2) <= '1';
					 display_placar1(0,3) <= '1';
					 display_placar1(0,4) <= '0';
					 
					 display_placar1(1,0) <= '0';
					 display_placar1(1,1) <= '0';
					 display_placar1(1,2) <= '0';
					 display_placar1(1,3) <= '0';
					 display_placar1(1,4) <= '1';
					 
					 display_placar1(2,0) <= '0';
					 display_placar1(2,1) <= '1';
					 display_placar1(2,2) <= '1';
					 display_placar1(2,3) <= '1';
					 display_placar1(2,4) <= '1';
					 
					 display_placar1(3,0) <= '1';
					 display_placar1(3,1) <= '0';
					 display_placar1(3,2) <= '0';
					 display_placar1(3,3) <= '0';
					 display_placar1(3,4) <= '0';
					 
					 display_placar1(4,0) <= '1';
					 display_placar1(4,1) <= '1';
					 display_placar1(4,2) <= '1';
					 display_placar1(4,3) <= '1';
					 display_placar1(4,4) <= '1';
		
		elsif pontos_PAD1 = 3 then
			       display_placar1(0,0) <= '1';
					 display_placar1(0,1) <= '1';
					 display_placar1(0,2) <= '1';
					 display_placar1(0,3) <= '1';
					 display_placar1(0,4) <= '0';
					 
					 display_placar1(1,0) <= '0';
					 display_placar1(1,1) <= '0';
					 display_placar1(1,2) <= '0';
					 display_placar1(1,3) <= '0';
					 display_placar1(1,4) <= '1';
					 
					 display_placar1(2,0) <= '0';
					 display_placar1(2,1) <= '1';
					 display_placar1(2,2) <= '1';
					 display_placar1(2,3) <= '1';
					 display_placar1(2,4) <= '1';
					 
					 display_placar1(3,0) <= '0';
					 display_placar1(3,1) <= '0';
					 display_placar1(3,2) <= '0';
					 display_placar1(3,3) <= '0';
					 display_placar1(3,4) <= '1';
					 
					 display_placar1(4,0) <= '1';
					 display_placar1(4,1) <= '1';
					 display_placar1(4,2) <= '1';
					 display_placar1(4,3) <= '1';
					 display_placar1(4,4) <= '0';
		
		elsif pontos_PAD1 = 4 then
			       display_placar1(0,0) <= '1';
					 display_placar1(0,1) <= '0';
					 display_placar1(0,2) <= '0';
					 display_placar1(0,3) <= '0';
					 display_placar1(0,4) <= '1';
					 
					 display_placar1(1,0) <= '1';
					 display_placar1(1,1) <= '0';
					 display_placar1(1,2) <= '0';
					 display_placar1(1,3) <= '0';
					 display_placar1(1,4) <= '1';
					 
					 display_placar1(2,0) <= '1';
					 display_placar1(2,1) <= '1';
					 display_placar1(2,2) <= '1';
					 display_placar1(2,3) <= '1';
					 display_placar1(2,4) <= '1';
					 
					 display_placar1(3,0) <= '0';
					 display_placar1(3,1) <= '0';
					 display_placar1(3,2) <= '0';
					 display_placar1(3,3) <= '0';
					 display_placar1(3,4) <= '1';
					 
					 display_placar1(4,0) <= '0';
					 display_placar1(4,1) <= '0';
					 display_placar1(4,2) <= '0';
					 display_placar1(4,3) <= '0';
					 display_placar1(4,4) <= '1';
		
		elsif pontos_PAD1 = 5 then
			       display_placar1(0,0) <= '1';
					 display_placar1(0,1) <= '1';
					 display_placar1(0,2) <= '1';
					 display_placar1(0,3) <= '1';
					 display_placar1(0,4) <= '1';
					 
					 display_placar1(1,0) <= '1';
					 display_placar1(1,1) <= '0';
					 display_placar1(1,2) <= '0';
					 display_placar1(1,3) <= '0';
					 display_placar1(1,4) <= '0';
					 
					 display_placar1(2,0) <= '1';
					 display_placar1(2,1) <= '1';
					 display_placar1(2,2) <= '1';
					 display_placar1(2,3) <= '1';
					 display_placar1(2,4) <= '0';
					 
					 display_placar1(3,0) <= '0';
					 display_placar1(3,1) <= '0';
					 display_placar1(3,2) <= '0';
					 display_placar1(3,3) <= '0';
					 display_placar1(3,4) <= '1';
					 
					 display_placar1(4,0) <= '1';
					 display_placar1(4,1) <= '1';
					 display_placar1(4,2) <= '1';
					 display_placar1(4,3) <= '1';
					 display_placar1(4,4) <= '0';
		
		elsif pontos_PAD1 = 6 then
			       display_placar1(0,0) <= '0';
					 display_placar1(0,1) <= '1';
					 display_placar1(0,2) <= '1';
					 display_placar1(0,3) <= '1';
					 display_placar1(0,4) <= '0';
					 
					 display_placar1(1,0) <= '1';
					 display_placar1(1,1) <= '0';
					 display_placar1(1,2) <= '0';
					 display_placar1(1,3) <= '0';
					 display_placar1(1,4) <= '0';
					 
					 display_placar1(2,0) <= '1';
					 display_placar1(2,1) <= '1';
					 display_placar1(2,2) <= '1';
					 display_placar1(2,3) <= '1';
					 display_placar1(2,4) <= '0';
					 
					 display_placar1(3,0) <= '1';
					 display_placar1(3,1) <= '0';
					 display_placar1(3,2) <= '0';
					 display_placar1(3,3) <= '0';
					 display_placar1(3,4) <= '1';
					 
					 display_placar1(4,0) <= '0';
					 display_placar1(4,1) <= '1';
					 display_placar1(4,2) <= '1';
					 display_placar1(4,3) <= '1';
					 display_placar1(4,4) <= '0';
		
		else
			       display_placar1(0,0) <= '1';
					 display_placar1(0,1) <= '1';
					 display_placar1(0,2) <= '1';
					 display_placar1(0,3) <= '1';
					 display_placar1(0,4) <= '1';
					 
					 display_placar1(1,0) <= '0';
					 display_placar1(1,1) <= '0';
					 display_placar1(1,2) <= '0';
					 display_placar1(1,3) <= '0';
					 display_placar1(1,4) <= '1';
					 
					 display_placar1(2,0) <= '0';
					 display_placar1(2,1) <= '0';
					 display_placar1(2,2) <= '0';
					 display_placar1(2,3) <= '0';
					 display_placar1(2,4) <= '1';
					 
					 display_placar1(3,0) <= '0';
					 display_placar1(3,1) <= '0';
					 display_placar1(3,2) <= '0';
					 display_placar1(3,3) <= '1';
					 display_placar1(3,4) <= '0';
					 
					 display_placar1(4,0) <= '0';
					 display_placar1(4,1) <= '0';
					 display_placar1(4,2) <= '0';
					 display_placar1(4,3) <= '1';
					 display_placar1(4,4) <= '0';
		end if;
		
		if pontos_PAD2 = 0 then
			       display_placar2(0,0) <= '0';
					 display_placar2(0,1) <= '1';
					 display_placar2(0,2) <= '1';
					 display_placar2(0,3) <= '1';
					 display_placar2(0,4) <= '0';
					 display_placar2(1,0) <= '1';
					 display_placar2(1,1) <= '0';
					 display_placar2(1,2) <= '0';
					 display_placar2(1,3) <= '0';
					 display_placar2(1,4) <= '1';
					 display_placar2(2,0) <= '1';
					 display_placar2(2,1) <= '0';
					 display_placar2(2,2) <= '0';
					 display_placar2(2,3) <= '0';
					 display_placar2(2,4) <= '1';
					 display_placar2(3,0) <= '1';
					 display_placar2(3,1) <= '0';
					 display_placar2(3,2) <= '0';
					 display_placar2(3,3) <= '0';
					 display_placar2(3,4) <= '1';				 
					 display_placar2(4,0) <= '0';
					 display_placar2(4,1) <= '1';
					 display_placar2(4,2) <= '1';
					 display_placar2(4,3) <= '1';
					 display_placar2(4,4) <= '0';
		
		elsif pontos_PAD2 = 1 then
			       display_placar2(0,0) <= '0';
					 display_placar2(0,1) <= '0';
					 display_placar2(0,2) <= '1';
					 display_placar2(0,3) <= '1';
					 display_placar2(0,4) <= '0';
					 
					 display_placar2(1,0) <= '0';
					 display_placar2(1,1) <= '0';
					 display_placar2(1,2) <= '0';
					 display_placar2(1,3) <= '1';
					 display_placar2(1,4) <= '0';
					 
					 display_placar2(2,0) <= '0';
					 display_placar2(2,1) <= '0';
					 display_placar2(2,2) <= '0';
					 display_placar2(2,3) <= '1';
					 display_placar2(2,4) <= '0';
					 
					 display_placar2(3,0) <= '0';
					 display_placar2(3,1) <= '0';
					 display_placar2(3,2) <= '0';
					 display_placar2(3,3) <= '1';
					 display_placar2(3,4) <= '0';
					 
					 display_placar2(4,0) <= '0';
					 display_placar2(4,1) <= '0';
					 display_placar2(4,2) <= '0';
					 display_placar2(4,3) <= '1';
					 display_placar2(4,4) <= '0';
		
		elsif pontos_PAD2 = 2 then
			       display_placar2(0,0) <= '1';
					 display_placar2(0,1) <= '1';
					 display_placar2(0,2) <= '1';
					 display_placar2(0,3) <= '1';
					 display_placar2(0,4) <= '0';
					 
					 display_placar2(1,0) <= '0';
					 display_placar2(1,1) <= '0';
					 display_placar2(1,2) <= '0';
					 display_placar2(1,3) <= '0';
					 display_placar2(1,4) <= '1';
					 
					 display_placar2(2,0) <= '0';
					 display_placar2(2,1) <= '1';
					 display_placar2(2,2) <= '1';
					 display_placar2(2,3) <= '1';
					 display_placar2(2,4) <= '1';
					 
					 display_placar2(3,0) <= '1';
					 display_placar2(3,1) <= '0';
					 display_placar2(3,2) <= '0';
					 display_placar2(3,3) <= '0';
					 display_placar2(3,4) <= '0';
					 
					 display_placar2(4,0) <= '1';
					 display_placar2(4,1) <= '1';
					 display_placar2(4,2) <= '1';
					 display_placar2(4,3) <= '1';
					 display_placar2(4,4) <= '1';
		
		elsif pontos_PAD2 = 3 then
			       display_placar2(0,0) <= '1';
					 display_placar2(0,1) <= '1';
					 display_placar2(0,2) <= '1';
					 display_placar2(0,3) <= '1';
					 display_placar2(0,4) <= '0';
					 
					 display_placar2(1,0) <= '0';
					 display_placar2(1,1) <= '0';
					 display_placar2(1,2) <= '0';
					 display_placar2(1,3) <= '0';
					 display_placar2(1,4) <= '1';
					 
					 display_placar2(2,0) <= '0';
					 display_placar2(2,1) <= '1';
					 display_placar2(2,2) <= '1';
					 display_placar2(2,3) <= '1';
					 display_placar2(2,4) <= '1';
					 
					 display_placar2(3,0) <= '0';
					 display_placar2(3,1) <= '0';
					 display_placar2(3,2) <= '0';
					 display_placar2(3,3) <= '0';
					 display_placar2(3,4) <= '1';
					 
					 display_placar2(4,0) <= '1';
					 display_placar2(4,1) <= '1';
					 display_placar2(4,2) <= '1';
					 display_placar2(4,3) <= '1';
					 display_placar2(4,4) <= '0';
		
		elsif pontos_PAD2 = 4 then
			       display_placar2(0,0) <= '1';
					 display_placar2(0,1) <= '0';
					 display_placar2(0,2) <= '0';
					 display_placar2(0,3) <= '0';
					 display_placar2(0,4) <= '1';
					 
					 display_placar2(1,0) <= '1';
					 display_placar2(1,1) <= '0';
					 display_placar2(1,2) <= '0';
					 display_placar2(1,3) <= '0';
					 display_placar2(1,4) <= '1';
					 
					 display_placar2(2,0) <= '1';
					 display_placar2(2,1) <= '1';
					 display_placar2(2,2) <= '1';
					 display_placar2(2,3) <= '1';
					 display_placar2(2,4) <= '1';
					 
					 display_placar2(3,0) <= '0';
					 display_placar2(3,1) <= '0';
					 display_placar2(3,2) <= '0';
					 display_placar2(3,3) <= '0';
					 display_placar2(3,4) <= '1';
					 
					 display_placar2(4,0) <= '0';
					 display_placar2(4,1) <= '0';
					 display_placar2(4,2) <= '0';
					 display_placar2(4,3) <= '0';
					 display_placar2(4,4) <= '1';
		
		elsif pontos_PAD2 = 5 then
			       display_placar2(0,0) <= '1';
					 display_placar2(0,1) <= '1';
					 display_placar2(0,2) <= '1';
					 display_placar2(0,3) <= '1';
					 display_placar2(0,4) <= '1';
					 
					 display_placar2(1,0) <= '1';
					 display_placar2(1,1) <= '0';
					 display_placar2(1,2) <= '0';
					 display_placar2(1,3) <= '0';
					 display_placar2(1,4) <= '0';
					 
					 display_placar2(2,0) <= '1';
					 display_placar2(2,1) <= '1';
					 display_placar2(2,2) <= '1';
					 display_placar2(2,3) <= '1';
					 display_placar2(2,4) <= '0';
					 
					 display_placar2(3,0) <= '0';
					 display_placar2(3,1) <= '0';
					 display_placar2(3,2) <= '0';
					 display_placar2(3,3) <= '0';
					 display_placar2(3,4) <= '1';
					 
					 display_placar2(4,0) <= '1';
					 display_placar2(4,1) <= '1';
					 display_placar2(4,2) <= '1';
					 display_placar2(4,3) <= '1';
					 display_placar2(4,4) <= '0';
	
		elsif pontos_PAD2 = 6 then
			       display_placar2(0,0) <= '0';
					 display_placar2(0,1) <= '1';
					 display_placar2(0,2) <= '1';
					 display_placar2(0,3) <= '1';
					 display_placar2(0,4) <= '0';
					 
					 display_placar2(1,0) <= '1';
					 display_placar2(1,1) <= '0';
					 display_placar2(1,2) <= '0';
					 display_placar2(1,3) <= '0';
					 display_placar2(1,4) <= '0';
					 
					 display_placar2(2,0) <= '1';
					 display_placar2(2,1) <= '1';
					 display_placar2(2,2) <= '1';
					 display_placar2(2,3) <= '1';
					 display_placar2(2,4) <= '0';
					 
					 display_placar2(3,0) <= '1';
					 display_placar2(3,1) <= '0';
					 display_placar2(3,2) <= '0';
					 display_placar2(3,3) <= '0';
					 display_placar2(3,4) <= '1';
					 
					 display_placar2(4,0) <= '0';
					 display_placar2(4,1) <= '1';
					 display_placar2(4,2) <= '1';
					 display_placar2(4,3) <= '1';
					 display_placar2(4,4) <= '0';
		
		else
			       display_placar2(0,0) <= '1';
					 display_placar2(0,1) <= '1';
					 display_placar2(0,2) <= '1';
					 display_placar2(0,3) <= '1';
					 display_placar2(0,4) <= '1';
					 
					 display_placar2(1,0) <= '0';
					 display_placar2(1,1) <= '0';
					 display_placar2(1,2) <= '0';
					 display_placar2(1,3) <= '0';
					 display_placar2(1,4) <= '1';
					 
					 display_placar2(2,0) <= '0';
					 display_placar2(2,1) <= '0';
					 display_placar2(2,2) <= '0';
					 display_placar2(2,3) <= '0';
					 display_placar2(2,4) <= '1';
					 
					 display_placar2(3,0) <= '0';
					 display_placar2(3,1) <= '0';
					 display_placar2(3,2) <= '0';
					 display_placar2(3,3) <= '1';
					 display_placar2(3,4) <= '0';
					 
					 display_placar2(4,0) <= '0';
					 display_placar2(4,1) <= '0';
					 display_placar2(4,2) <= '0';
					 display_placar2(4,3) <= '1';
					 display_placar2(4,4) <= '0';
		end if;
	end process;
	
	-- Mensagens do comeco e fim da partida
	process(flag_inicio, flag_fim)
	begin
		-- mensagem final de cada partida
		if pontos_PAD1 >=7 or pontos_PAD2 >= 7  then
			display_mensagem(0,0) <= '1'; --P
			display_mensagem(1,0) <= '1';
			display_mensagem(2,0) <= '1';
			display_mensagem(3,0) <= '1';
			display_mensagem(4,0) <= '1';
			display_mensagem(0,1) <= '1';
			display_mensagem(1,1) <= '0';
			display_mensagem(2,1) <= '1';
			display_mensagem(3,1) <= '0';
			display_mensagem(4,1) <= '0';
			display_mensagem(0,2) <= '1';
			display_mensagem(1,2) <= '1';
			display_mensagem(2,2) <= '1';
			display_mensagem(3,2) <= '0';
			display_mensagem(4,2) <= '0';
			
			display_mensagem(0,3) <= '0';
			display_mensagem(1,3) <= '0';
			display_mensagem(2,3) <= '0';
			display_mensagem(3,3) <= '0';
			display_mensagem(4,3) <= '0';
			-- 1 ou 2, decidido qual mais embaixo
			
			display_mensagem(0,7) <= '0'; --espaco
			display_mensagem(1,7) <= '0';
			display_mensagem(2,7) <= '0';
			display_mensagem(3,7) <= '0';
			display_mensagem(4,7) <= '0';
			display_mensagem(0,8) <= '0';
			display_mensagem(1,8) <= '0';
			display_mensagem(2,8) <= '0';
			display_mensagem(3,8) <= '0';
			display_mensagem(4,8) <= '0';
			display_mensagem(0,9) <= '0';
			display_mensagem(1,9) <= '0';
			display_mensagem(2,9) <= '0';
			display_mensagem(3,9) <= '0';
			display_mensagem(4,9) <= '0';
			display_mensagem(0,10) <= '0';
			display_mensagem(1,10) <= '0';
			display_mensagem(2,10) <= '0';
			display_mensagem(3,10) <= '0';
			display_mensagem(4,10) <= '0';
			display_mensagem(0,11) <= '0';
			display_mensagem(1,11) <= '0';
			display_mensagem(2,11) <= '0';
			display_mensagem(3,11) <= '0';
			display_mensagem(4,11) <= '0';
			
			display_mensagem(0,12) <= '1'; --G
			display_mensagem(1,12) <= '1';
			display_mensagem(2,12) <= '1';
			display_mensagem(3,12) <= '1';
			display_mensagem(4,12) <= '1';
			display_mensagem(0,13) <= '1';
			display_mensagem(1,13) <= '0';
			display_mensagem(2,13) <= '1';
			display_mensagem(3,13) <= '0';
			display_mensagem(4,13) <= '1';
			display_mensagem(0,14) <= '0';
			display_mensagem(1,14) <= '0';
			display_mensagem(2,14) <= '1';
			display_mensagem(3,14) <= '1';
			display_mensagem(4,14) <= '1';
			
			display_mensagem(0,15) <= '0';
			display_mensagem(1,15) <= '0';
			display_mensagem(2,15) <= '0';
			display_mensagem(3,15) <= '0';
			display_mensagem(4,15) <= '0';
			
			display_mensagem(0,16) <= '1'; --A
			display_mensagem(1,16) <= '1';
			display_mensagem(2,16) <= '1';
			display_mensagem(3,16) <= '1';
			display_mensagem(4,16) <= '1';
			display_mensagem(0,17) <= '1';
			display_mensagem(1,17) <= '0';
			display_mensagem(2,17) <= '1';
			display_mensagem(3,17) <= '0';
			display_mensagem(4,17) <= '0';
			display_mensagem(0,18) <= '1';
			display_mensagem(1,18) <= '1';
			display_mensagem(2,18) <= '1';
			display_mensagem(3,18) <= '1';
			display_mensagem(4,18) <= '1';
			
			display_mensagem(0,19) <= '0';
			display_mensagem(1,19) <= '0';
			display_mensagem(2,19) <= '0';
			display_mensagem(3,19) <= '0';
			display_mensagem(4,19) <= '0';
			
			display_mensagem(0,20) <= '1'; --N
			display_mensagem(1,20) <= '1';
			display_mensagem(2,20) <= '1';
			display_mensagem(3,20) <= '1';
			display_mensagem(4,20) <= '1';
			display_mensagem(0,21) <= '1';
			display_mensagem(1,21) <= '0';
			display_mensagem(2,21) <= '0';
			display_mensagem(3,21) <= '0';
			display_mensagem(4,21) <= '0';
			display_mensagem(0,22) <= '1';
			display_mensagem(1,22) <= '1';
			display_mensagem(2,22) <= '1';
			display_mensagem(3,22) <= '1';
			display_mensagem(4,22) <= '1';
			
			display_mensagem(0,23) <= '0';
			display_mensagem(1,23) <= '0';
			display_mensagem(2,23) <= '0';
			display_mensagem(3,23) <= '0';
			display_mensagem(4,23) <= '0';
			
			display_mensagem(0,24) <= '1'; --H
			display_mensagem(1,24) <= '1';
			display_mensagem(2,24) <= '1';
			display_mensagem(3,24) <= '1';
			display_mensagem(4,24) <= '1';
			display_mensagem(0,25) <= '0';
			display_mensagem(1,25) <= '0';
			display_mensagem(2,25) <= '1';
			display_mensagem(3,25) <= '0';
			display_mensagem(4,25) <= '0';
			display_mensagem(0,26) <= '1';
			display_mensagem(1,26) <= '1';
			display_mensagem(2,26) <= '1';
			display_mensagem(3,26) <= '1';
			display_mensagem(4,26) <= '1';
			
			display_mensagem(0,27) <= '0';
			display_mensagem(1,27) <= '0';
			display_mensagem(2,27) <= '0';
			display_mensagem(3,27) <= '0';
			display_mensagem(4,27) <= '0';
			
			display_mensagem(0,28) <= '1'; --O
			display_mensagem(1,28) <= '1';
			display_mensagem(2,28) <= '1';
			display_mensagem(3,28) <= '1';
			display_mensagem(4,28) <= '1';
			display_mensagem(0,29) <= '1';
			display_mensagem(1,29) <= '0';
			display_mensagem(2,29) <= '0';
			display_mensagem(3,29) <= '0';
			display_mensagem(4,29) <= '1';
			display_mensagem(0,30) <= '1';
			display_mensagem(1,30) <= '1';
			display_mensagem(2,30) <= '1';
			display_mensagem(3,30) <= '1';
			display_mensagem(4,30) <= '1';
			
			display_mensagem(0,31) <= '0';
			display_mensagem(1,31) <= '0';
			display_mensagem(2,31) <= '0';
			display_mensagem(3,31) <= '0';
			display_mensagem(4,31) <= '0';
			
			display_mensagem(0,32) <= '1'; --U
			display_mensagem(1,32) <= '1';
			display_mensagem(2,32) <= '1';
			display_mensagem(3,32) <= '1';
			display_mensagem(4,32) <= '1';
			display_mensagem(0,33) <= '0';
			display_mensagem(1,33) <= '0';
			display_mensagem(2,33) <= '0';
			display_mensagem(3,33) <= '0';
			display_mensagem(4,33) <= '1';
			display_mensagem(0,34) <= '1';
			display_mensagem(1,34) <= '1';
			display_mensagem(2,34) <= '1';
			display_mensagem(3,34) <= '1';
			display_mensagem(4,34) <= '1';
			
			display_mensagem(0,35) <= '0';
			display_mensagem(1,35) <= '0';
			display_mensagem(2,35) <= '0';
			display_mensagem(3,35) <= '0';
			display_mensagem(4,35) <= '0';
			
			display_mensagem(0,36) <= '1'; --!
			display_mensagem(1,36) <= '1';
			display_mensagem(2,36) <= '1';
			display_mensagem(3,36) <= '0';
			display_mensagem(4,36) <= '1';
			display_mensagem(0,37) <= '0';
			display_mensagem(1,37) <= '0';
			display_mensagem(2,37) <= '0';
			display_mensagem(3,37) <= '0';
			display_mensagem(4,37) <= '0';
			display_mensagem(0,38) <= '0';
			display_mensagem(1,38) <= '0';
			display_mensagem(2,38) <= '0';
			display_mensagem(3,38) <= '0';
			display_mensagem(4,38) <= '0';
			
			display_mensagem(0,39) <= '0'; --=]
			display_mensagem(1,39) <= '0';
			display_mensagem(2,39) <= '0';
			display_mensagem(3,39) <= '1';
			display_mensagem(4,39) <= '1';
			display_mensagem(0,40) <= '0';
			display_mensagem(1,40) <= '0';
			display_mensagem(2,40) <= '0';
			display_mensagem(3,40) <= '0';
			display_mensagem(4,40) <= '1';
			display_mensagem(0,41) <= '1';
			display_mensagem(1,41) <= '1';
			display_mensagem(2,41) <= '0';
			display_mensagem(3,41) <= '0';
			display_mensagem(4,41) <= '1';
			display_mensagem(0,42) <= '0';
			display_mensagem(1,42) <= '0';
			display_mensagem(2,42) <= '0';
			display_mensagem(3,42) <= '0';
			display_mensagem(4,42) <= '1';
			display_mensagem(0,43) <= '1';
			display_mensagem(1,43) <= '1';
			display_mensagem(2,43) <= '0';
			display_mensagem(3,43) <= '0';
			display_mensagem(4,43) <= '1';
			display_mensagem(0,44) <= '0';
			display_mensagem(1,44) <= '0';
			display_mensagem(2,44) <= '0';
			display_mensagem(3,44) <= '0';
			display_mensagem(4,44) <= '1';
			display_mensagem(0,45) <= '0';
			display_mensagem(1,45) <= '0';
			display_mensagem(2,45) <= '0';
			display_mensagem(3,45) <= '1';
			display_mensagem(4,45) <= '1';
			display_mensagem(0,46) <= '0';
			display_mensagem(1,46) <= '0';
			display_mensagem(2,46) <= '0';
			display_mensagem(3,46) <= '0';
			display_mensagem(4,46) <= '0';
				
			if pontos_PAD1 >= 7 then		
				display_mensagem(0,4) <= '0'; --1
				display_mensagem(1,4) <= '1';
				display_mensagem(2,4) <= '0';
				display_mensagem(3,4) <= '0';
				display_mensagem(4,4) <= '1';
				display_mensagem(0,5) <= '1';
				display_mensagem(1,5) <= '1';
				display_mensagem(2,5) <= '1';
				display_mensagem(3,5) <= '1';
				display_mensagem(4,5) <= '1';
				display_mensagem(0,6) <= '0';
				display_mensagem(1,6) <= '0';
				display_mensagem(2,6) <= '0';
				display_mensagem(3,6) <= '0';
				display_mensagem(4,6) <= '1';
			else
				display_mensagem(0,4) <= '1'; --2
				display_mensagem(1,4) <= '0';
				display_mensagem(2,4) <= '1';
				display_mensagem(3,4) <= '1';
				display_mensagem(4,4) <= '1';
				display_mensagem(0,5) <= '1';
				display_mensagem(1,5) <= '0';
				display_mensagem(2,5) <= '1';
				display_mensagem(3,5) <= '0';
				display_mensagem(4,5) <= '1';
				display_mensagem(0,6) <= '1';
				display_mensagem(1,6) <= '1';
				display_mensagem(2,6) <= '1';
				display_mensagem(3,6) <= '0';
				display_mensagem(4,6) <= '1';
			end if;
		
		elsif flag_inicio = '0' then -- mensagem inicial
			display_mensagem(0,0) <= '1'; --A
			display_mensagem(1,0) <= '1';
			display_mensagem(2,0) <= '1';
			display_mensagem(3,0) <= '1';
			display_mensagem(4,0) <= '1';
			display_mensagem(0,1) <= '1';
			display_mensagem(1,1) <= '0';
			display_mensagem(2,1) <= '1';
			display_mensagem(3,1) <= '0';
			display_mensagem(4,1) <= '0';
			display_mensagem(0,2) <= '1';
			display_mensagem(1,2) <= '1';
			display_mensagem(2,2) <= '1';
			display_mensagem(3,2) <= '1';
			display_mensagem(4,2) <= '1';
			
			display_mensagem(0,3) <= '0';
			display_mensagem(1,3) <= '0';
			display_mensagem(2,3) <= '0';
			display_mensagem(3,3) <= '0';
			display_mensagem(4,3) <= '0';
			
			display_mensagem(0,4) <= '1'; --P
			display_mensagem(1,4) <= '1';
			display_mensagem(2,4) <= '1';
			display_mensagem(3,4) <= '1';
			display_mensagem(4,4) <= '1';
			display_mensagem(0,5) <= '1';
			display_mensagem(1,5) <= '0';
			display_mensagem(2,5) <= '1';
			display_mensagem(3,5) <= '0';
			display_mensagem(4,5) <= '0';
			display_mensagem(0,6) <= '1';
			display_mensagem(1,6) <= '1';
			display_mensagem(2,6) <= '1';
			display_mensagem(3,6) <= '0';
			display_mensagem(4,6) <= '0';
			
			display_mensagem(0,7) <= '0';
			display_mensagem(1,7) <= '0';
			display_mensagem(2,7) <= '0';
			display_mensagem(3,7) <= '0';
			display_mensagem(4,7) <= '0';
			
			display_mensagem(0,8) <= '1'; --E
			display_mensagem(1,8) <= '1';
			display_mensagem(2,8) <= '1';
			display_mensagem(3,8) <= '1';
			display_mensagem(4,8) <= '1';
			display_mensagem(0,9) <= '1';
			display_mensagem(1,9) <= '0';
			display_mensagem(2,9) <= '1';
			display_mensagem(3,9) <= '0';
			display_mensagem(4,9) <= '1';
			display_mensagem(0,10) <= '1';
			display_mensagem(1,10) <= '0';
			display_mensagem(2,10) <= '0';
			display_mensagem(3,10) <= '0';
			display_mensagem(4,10) <= '1';
			
			display_mensagem(0,11) <= '0';
			display_mensagem(1,11) <= '0';
			display_mensagem(2,11) <= '0';
			display_mensagem(3,11) <= '0';
			display_mensagem(4,11) <= '0';
			
			display_mensagem(0,12) <= '1'; --R
			display_mensagem(1,12) <= '1';
			display_mensagem(2,12) <= '1';
			display_mensagem(3,12) <= '1';
			display_mensagem(4,12) <= '1';
			display_mensagem(0,13) <= '1';
			display_mensagem(1,13) <= '0';
			display_mensagem(2,13) <= '1';
			display_mensagem(3,13) <= '1';
			display_mensagem(4,13) <= '0';
			display_mensagem(0,14) <= '1';
			display_mensagem(1,14) <= '1';
			display_mensagem(2,14) <= '1';
			display_mensagem(3,14) <= '0';
			display_mensagem(4,14) <= '1';
			
			display_mensagem(0,15) <= '0';
			display_mensagem(1,15) <= '0';
			display_mensagem(2,15) <= '0';
			display_mensagem(3,15) <= '0';
			display_mensagem(4,15) <= '0';
			
			display_mensagem(0,16) <= '1'; --T
			display_mensagem(1,16) <= '0';
			display_mensagem(2,16) <= '0';
			display_mensagem(3,16) <= '0';
			display_mensagem(4,16) <= '0';
			display_mensagem(0,17) <= '1';
			display_mensagem(1,17) <= '1';
			display_mensagem(2,17) <= '1';
			display_mensagem(3,17) <= '1';
			display_mensagem(4,17) <= '1';
			display_mensagem(0,18) <= '1';
			display_mensagem(1,18) <= '0';
			display_mensagem(2,18) <= '0';
			display_mensagem(3,18) <= '0';
			display_mensagem(4,18) <= '0';
			
			display_mensagem(0,19) <= '0';
			display_mensagem(1,19) <= '0';
			display_mensagem(2,19) <= '0';
			display_mensagem(3,19) <= '0';
			display_mensagem(4,19) <= '0';
			
			display_mensagem(0,20) <= '1'; --E
			display_mensagem(1,20) <= '1';
			display_mensagem(2,20) <= '1';
			display_mensagem(3,20) <= '1';
			display_mensagem(4,20) <= '1';
			display_mensagem(0,21) <= '1';
			display_mensagem(1,21) <= '0';
			display_mensagem(2,21) <= '1';
			display_mensagem(3,21) <= '0';
			display_mensagem(4,21) <= '1';
			display_mensagem(0,22) <= '1';
			display_mensagem(1,22) <= '0';
			display_mensagem(2,22) <= '0';
			display_mensagem(3,22) <= '0';
			display_mensagem(4,22) <= '1';
			
			display_mensagem(0,23) <= '0'; --espaco
			display_mensagem(1,23) <= '0';
			display_mensagem(2,23) <= '0';
			display_mensagem(3,23) <= '0';
			display_mensagem(4,23) <= '0';
			display_mensagem(0,24) <= '0';
			display_mensagem(1,24) <= '0';
			display_mensagem(2,24) <= '0';
			display_mensagem(3,24) <= '0';
			display_mensagem(4,24) <= '0';
			display_mensagem(0,25) <= '0';
			display_mensagem(1,25) <= '0';
			display_mensagem(2,25) <= '0';
			display_mensagem(3,25) <= '0';
			display_mensagem(4,25) <= '0';
			display_mensagem(0,26) <= '0';
			display_mensagem(1,26) <= '0';
			display_mensagem(2,26) <= '0';
			display_mensagem(3,26) <= '0';
			display_mensagem(4,26) <= '0';
			display_mensagem(0,27) <= '0';
			display_mensagem(1,27) <= '0';
			display_mensagem(2,27) <= '0';
			display_mensagem(3,27) <= '0';
			display_mensagem(4,27) <= '0';
			
			display_mensagem(0,28) <= '1'; --E
			display_mensagem(1,28) <= '1';
			display_mensagem(2,28) <= '1';
			display_mensagem(3,28) <= '1';
			display_mensagem(4,28) <= '1';
			display_mensagem(0,29) <= '1';
			display_mensagem(1,29) <= '0';
			display_mensagem(2,29) <= '1';
			display_mensagem(3,29) <= '0';
			display_mensagem(4,29) <= '1';
			display_mensagem(0,30) <= '1';
			display_mensagem(1,30) <= '0';
			display_mensagem(2,30) <= '0';
			display_mensagem(3,30) <= '0';
			display_mensagem(4,30) <= '1';
			
			display_mensagem(0,31) <= '0';
			display_mensagem(1,31) <= '0';
			display_mensagem(2,31) <= '0';
			display_mensagem(3,31) <= '0';
			display_mensagem(4,31) <= '0';
			
			display_mensagem(0,32) <= '1'; --N
			display_mensagem(1,32) <= '1';
			display_mensagem(2,32) <= '1';
			display_mensagem(3,32) <= '1';
			display_mensagem(4,32) <= '1';
			display_mensagem(0,33) <= '1';
			display_mensagem(1,33) <= '0';
			display_mensagem(2,33) <= '0';
			display_mensagem(3,33) <= '0';
			display_mensagem(4,33) <= '0';
			display_mensagem(0,34) <= '1';
			display_mensagem(1,34) <= '1';
			display_mensagem(2,34) <= '1';
			display_mensagem(3,34) <= '1';
			display_mensagem(4,34) <= '1';
			
			display_mensagem(0,35) <= '0';
			display_mensagem(1,35) <= '0';
			display_mensagem(2,35) <= '0';
			display_mensagem(3,35) <= '0';
			display_mensagem(4,35) <= '0';
			
			display_mensagem(0,36) <= '1'; --T
			display_mensagem(1,36) <= '0';
			display_mensagem(2,36) <= '0';
			display_mensagem(3,36) <= '0';
			display_mensagem(4,36) <= '0';
			display_mensagem(0,37) <= '1';
			display_mensagem(1,37) <= '1';
			display_mensagem(2,37) <= '1';
			display_mensagem(3,37) <= '1';
			display_mensagem(4,37) <= '1';
			display_mensagem(0,38) <= '1';
			display_mensagem(1,38) <= '0';
			display_mensagem(2,38) <= '0';
			display_mensagem(3,38) <= '0';
			display_mensagem(4,38) <= '0';
			
			display_mensagem(0,39) <= '0';
			display_mensagem(1,39) <= '0';
			display_mensagem(2,39) <= '0';
			display_mensagem(3,39) <= '0';
			display_mensagem(4,39) <= '0';
			
			display_mensagem(0,40) <= '1'; --E
			display_mensagem(1,40) <= '1';
			display_mensagem(2,40) <= '1';
			display_mensagem(3,40) <= '1';
			display_mensagem(4,40) <= '1';
			display_mensagem(0,41) <= '1';
			display_mensagem(1,41) <= '0';
			display_mensagem(2,41) <= '1';
			display_mensagem(3,41) <= '0';
			display_mensagem(4,41) <= '1';
			display_mensagem(0,42) <= '1';
			display_mensagem(1,42) <= '0';
			display_mensagem(2,42) <= '0';
			display_mensagem(3,42) <= '0';
			display_mensagem(4,42) <= '1';
			
			display_mensagem(0,43) <= '0';
			display_mensagem(1,43) <= '0';
			display_mensagem(2,43) <= '0';
			display_mensagem(3,43) <= '0';
			display_mensagem(4,43) <= '0';
			
			display_mensagem(0,44) <= '1'; --R
			display_mensagem(1,44) <= '1';
			display_mensagem(2,44) <= '1';
			display_mensagem(3,44) <= '1';
			display_mensagem(4,44) <= '1';
			display_mensagem(0,45) <= '1';
			display_mensagem(1,45) <= '0';
			display_mensagem(2,45) <= '1';
			display_mensagem(3,45) <= '1';
			display_mensagem(4,45) <= '0';
			display_mensagem(0,46) <= '1';
			display_mensagem(1,46) <= '1';
			display_mensagem(2,46) <= '1';
			display_mensagem(3,46) <= '0';
			display_mensagem(4,46) <= '1';
			
		else
			display_mensagem(0,0) <= '0';
		end if;
	end process;
	
	 -----------------------------------------------------------------------------
  -- Brilho do pixel
  -----------------------------------------------------------------------------
  -- O brilho do pixel é branco quando os contadores de linha e coluna, que
  -- indicam o endereço do pixel sendo escrito para o quadro atual, casam com a
  -- posição da bola (sinais pos_bola_x e pos_bola_y), com a posição dos PADs, 
  -- com o placar ou com a mensagem.
  -- Caso contrário, o pixel é preto.

	process(CLOCK_50)
	begin
		if CLOCK_50'event and CLOCK_50 = '1' then
			if estado = constroi_quadro then
				-- Impressao das bolas e PADs
				if ((col = pos_bola_x) and (line = pos_bola_y)) 
											  or ((abs(line-pos_PAD1) < 4) and col = 10)
											  or ((abs(line-pos_PAD2) < 4) and col = 117) then
					pixel_bit <= '1';
				-- Placar do jogador 1
				elsif ((abs(line-5) < 3) and ((abs(col-55) < 3))) then
					pixel_bit <= display_placar1(line-3, col-53);
				-- Placar do jogador 2
				elsif ((abs(line-5) < 3) and ((abs(col-71) < 3))) then
					pixel_bit <= display_placar2(line-3, col-69);
				-- Mensagem do começo e fim do jogo
				elsif ((abs(line-25) < 3) and ((abs(col-63) < 24)) and ((flag_inicio = '0') or (flag_fim = '1')))then
					pixel_bit <= display_mensagem(line-23, col-40);
				else
					pixel_bit <= '0';	
				end if;
			end if;
		end if;
	end process;
	  
  pixel <= (others => pixel_bit);
  
  -- O endereço de memória pode ser construído com essa fórmula simples,
  -- a partir da linha e coluna atual
  addr  <= col + (128 * line);
  
  -----------------------------------------------------------------------------
  -- Processos que definem a FSM (finite state machine), nossa máquina
  -- de estados de controle.
  -----------------------------------------------------------------------------

  -- purpose: Esta é a lógica combinacional que calcula sinais de saída a partir
  --          do estado atual e alguns sinais de entrada (Máquina de Mealy).
  -- type   : combinational
  -- inputs : estado, fim_escrita, timer, flag_inicio
  -- outputs: proximo_estado, atualiza_pos_bola_x, atualiza_pos_bola_y, atualiza_pos_PADs, 
  --          line_rstn, line_enable, col_rstn, col_enable, we, timer_enable, timer_rstn
  logica_mealy: process (estado, fim_escrita, timer, flag_inicio)
  begin  -- process logica_mealy
    case estado is
    when inicio_jogo      => if flag_inicio = '1' then
										 proximo_estado <= inicio_partida;
									  elsif timer = '1' then
										 proximo_estado <= constroi_quadro;
                             else
										 proximo_estado <= inicio_jogo;
                             end if;
                             atualiza_pos_bola_x <= '0';
                             atualiza_pos_bola_y <= '0';
									  atualiza_pos_PADs   <= '0';
									  flag_inicio_rstn <= '1';
                             line_rstn      <= '0';  -- reset é active low!
                             line_enable    <= '0';
                             col_rstn       <= '0';  -- reset é active low!
                             col_enable     <= '0';
                             we             <= '0';
                             timer_rstn     <= '1';  -- reset é active low!
                             timer_enable   <= '1';
									  
    when inicio_partida   => if timer = '1' then              
                               proximo_estado <= constroi_quadro;
                             else
                               proximo_estado <= inicio_partida;
                             end if;
                             atualiza_pos_bola_x <= '0';
                             atualiza_pos_bola_y <= '0';
									  atualiza_pos_PADs   <= '0';
									  flag_inicio_rstn <= '1';
                             line_rstn      <= '0';  -- reset é active low!
                             line_enable    <= '0';
                             col_rstn       <= '0';  -- reset é active low!
                             col_enable     <= '0';
                             we             <= '0';
                             timer_rstn     <= '1';  -- reset é active low!
                             timer_enable   <= '1';

    when constroi_quadro  => if fim_escrita = '1' then
										if flag_fim = '1' then
											proximo_estado <= game_over;
											flag_inicio_rstn <= '0';
										elsif flag_inicio = '1' then
											proximo_estado <= move_bola_e_PADs;
											flag_inicio_rstn <= '1';
										else
											proximo_estado <= inicio_jogo;
											flag_inicio_rstn <= '1';
										end if;
                             else
                               proximo_estado <= constroi_quadro;
										 flag_inicio_rstn <= '1';
                             end if;
                             atualiza_pos_bola_x <= '0';
                             atualiza_pos_bola_y <= '0';
									  atualiza_pos_PADs   <= '0';		 
                             line_rstn      <= '1';
                             line_enable    <= '1';
                             col_rstn       <= '1';
                             col_enable     <= '1';
                             we             <= '1';
                             timer_rstn     <= '0'; 
                             timer_enable   <= '0';

    when move_bola_e_PADs => if flag_fim = '1' then
										proximo_estado <= game_over;
										flag_inicio_rstn <= '0';
									  else
										proximo_estado <= inicio_partida;
										flag_inicio_rstn <= '1';
									  end if;
                             atualiza_pos_bola_x <= '1';
                             atualiza_pos_bola_y <= '1';
									  atualiza_pos_PADs   <= '1';
                             line_rstn      <= '1';
                             line_enable    <= '0';
                             col_rstn       <= '1';
                             col_enable     <= '0';
                             we             <= '0';
                             timer_rstn     <= '0'; 
                             timer_enable   <= '0';
		
     when game_over       => if flag_inicio = '1' then
										proximo_estado <= inicio_jogo;
									  else
										proximo_estado <= constroi_quadro;
									  end if;
                             atualiza_pos_bola_x <= '0';
                             atualiza_pos_bola_y <= '0';
									  atualiza_pos_PADs   <= '0';
									  flag_inicio_rstn <= '1';
                             line_rstn      <= '0';
                             line_enable    <= '0';
                             col_rstn       <= '0';
                             col_enable     <= '0';
                             we             <= '0';
                             timer_rstn     <= '0';
                             timer_enable   <= '0';
									  
     when others          => proximo_estado <= inicio_partida;
                             atualiza_pos_bola_x <= '0';
                             atualiza_pos_bola_y <= '0';
									  atualiza_pos_PADs   <= '0';
									  flag_inicio_rstn <= '1';
                             line_rstn      <= '1';
                             line_enable    <= '0';
                             col_rstn       <= '1';
                             col_enable     <= '0';
                             we             <= '0';
                             timer_rstn     <= '1'; 
                             timer_enable   <= '0';
      
    end case;
  end process logica_mealy;
  
  -- purpose: Avança a FSM para o próximo estado
  -- type   : sequential
  -- inputs : CLOCK_50, proximo_estado
  -- outputs: estado
  seq_fsm: process (CLOCK_50)
  begin  -- process seq_fsm
    if CLOCK_50'event and CLOCK_50 = '1' then  -- rising clock edge
      estado <= proximo_estado;
    end if;
  end process seq_fsm;

  -----------------------------------------------------------------------------
  -- Processos do contador utilizado para atrasar a animação (evitar
  -- que a atualização de quadros fique excessivamente veloz).
  -----------------------------------------------------------------------------
  -- purpose: Incrementa o contador a cada ciclo de clock
  -- type   : sequential
  -- inputs : CLOCK_50, timer_rstn
  -- outputs: contador, timer
  p_contador: process (CLOCK_50, timer_rstn)
  begin  -- process p_contador
    if timer_rstn = '0' then            -- asynchronous reset (active low)
      contador <= 0;
    elsif CLOCK_50'event and CLOCK_50 = '1' then  -- rising clock edge
      if timer_enable = '1' then       
        if contador = 1250000 - 1 then
          contador <= 0;
        else
          contador <=  contador + 1;        
        end if;
      end if;
    end if;
  end process p_contador;

  -- purpose: Calcula o sinal "timer" que indica quando o contador chegou ao
  --          final
  -- type   : combinational
  -- inputs : contador
  -- outputs: timer
  p_timer: process (contador)
  begin  -- process p_timer
    if contador = 1250000 - 1 then
      timer <= '1';
    else
      timer <= '0';
    end if;
  end process p_timer;

end comportamento;
