import random
import sys

import pygame

CELL = 30
COLS = 10
ROWS = 20
BOARD_W = COLS * CELL
BOARD_H = ROWS * CELL
PANEL_W = 220
SCREEN_W = BOARD_W + PANEL_W
SCREEN_H = BOARD_H + 40
BOARD_X = 20
BOARD_Y = 20

GRAVITY_MS = 1000
CLEAR_ANIM_MS = 600
FPS = 60

BG_COLOR = (18, 18, 24)
PANEL_COLOR = (28, 28, 38)
GRID_COLOR = (45, 45, 60)
BORDER_COLOR = (90, 90, 110)
TEXT_COLOR = (230, 230, 240)
DIM_COLOR = (150, 150, 170)
OVERLAY_COLOR = (0, 0, 0, 180)

SHAPE_COLORS = {
    "I": (0, 200, 220),
    "O": (240, 210, 60),
    "T": (170, 80, 220),
    "L": (240, 140, 40),
}

SHAPES = {
    "I": [(0, 1), (1, 1), (2, 1), (3, 1)],
    "O": [(1, 0), (2, 0), (1, 1), (2, 1)],
    "T": [(1, 0), (0, 1), (1, 1), (2, 1)],
    "L": [(0, 0), (0, 1), (1, 1), (2, 1)],
}

WALL_KICKS = [0, -1, 1, -2, 2]


class Piece:
    def __init__(self, kind):
        self.kind = kind
        self.color = SHAPE_COLORS[kind]
        self.cells = list(SHAPES[kind])
        self.x = 0
        self.y = 0

    def rotated_cw(self):
        rotated = [(-y, x) for (x, y) in self.cells]
        min_x = min(c[0] for c in rotated)
        min_y = min(c[1] for c in rotated)
        return [(x - min_x, y - min_y) for (x, y) in rotated]

    def absolute_cells(self, dx=0, dy=0, cells=None):
        src = self.cells if cells is None else cells
        return [(self.x + cx + dx, self.y + cy + dy) for (cx, cy) in src]

    def spawn_position(self):
        width = max(cx for (cx, _) in self.cells) + 1
        self.x = (COLS - width) // 2
        self.y = 0


class Game:
    def __init__(self):
        self.reset()

    def reset(self):
        self.board = [[None] * COLS for _ in range(ROWS)]
        self.score = 0
        self.gravity_timer = 0
        self.clear_timer = 0
        self.clearing_rows = []
        self.paused = False
        self.game_over = False
        self.current = None
        self.next_kind = random.choice(list(SHAPES))
        self._spawn()

    def _spawn(self):
        kind = self.next_kind
        self.next_kind = random.choice(list(SHAPES))
        self.current = Piece(kind)
        self.current.spawn_position()
        self.gravity_timer = 0
        if self._collides(self.current.absolute_cells()):
            self.game_over = True

    def _collides(self, cells):
        for (x, y) in cells:
            if x < 0 or x >= COLS or y >= ROWS:
                return True
            if y >= 0 and self.board[y][x] is not None:
                return True
        return False

    def _busy(self):
        return self.game_over or self.paused or self.clearing_rows

    def move(self, dx, dy):
        if self._busy():
            return False
        cells = self.current.absolute_cells(dx, dy)
        if not self._collides(cells):
            self.current.x += dx
            self.current.y += dy
            return True
        return False

    def rotate(self):
        if self._busy():
            return
        rotated = self.current.rotated_cw()
        for kick in WALL_KICKS:
            cells = self.current.absolute_cells(kick, 0, rotated)
            if not self._collides(cells):
                self.current.cells = rotated
                self.current.x += kick
                return

    def soft_drop(self):
        if self._busy():
            return
        if self.move(0, 1):
            self.gravity_timer = 0
        else:
            self._lock()

    def hard_drop(self):
        if self._busy():
            return
        while not self._collides(self.current.absolute_cells(0, 1)):
            self.current.y += 1
        self._lock()

    def _lock(self):
        for (x, y) in self.current.absolute_cells():
            if 0 <= y < ROWS and 0 <= x < COLS:
                self.board[y][x] = self.current.color
        rows = [y for y in range(ROWS)
                if all(cell is not None for cell in self.board[y])]
        if rows:
            self.clearing_rows = rows
            self.clear_timer = 0
        else:
            self.current = None
            self._spawn()

    def _finish_clear(self):
        remaining = [row for y, row in enumerate(self.board)
                     if y not in self.clearing_rows]
        self.score += 100 * len(self.clearing_rows)
        self.board = [[None] * COLS] * len(self.clearing_rows) + remaining
        self.clearing_rows = []
        self.clear_timer = 0
        self.current = None
        self._spawn()

    def update(self, dt_ms):
        if self.game_over or self.paused:
            return
        if self.clearing_rows:
            self.clear_timer += dt_ms
            if self.clear_timer >= CLEAR_ANIM_MS:
                self._finish_clear()
            return
        self.gravity_timer += dt_ms
        while self.gravity_timer >= GRAVITY_MS:
            self.gravity_timer -= GRAVITY_MS
            if not self.move(0, 1):
                self._lock()
                if self.clearing_rows or self.game_over:
                    self.gravity_timer = 0
                    break


class Renderer:
    def __init__(self, screen):
        self.screen = screen
        self.font_big = pygame.font.SysFont("consolas", 34, bold=True)
        self.font_med = pygame.font.SysFont("consolas", 22, bold=True)
        self.font_small = pygame.font.SysFont("consolas", 16)

    def draw_block(self, x, y, color, size=CELL):
        rect = pygame.Rect(x, y, size, size)
        pygame.draw.rect(self.screen, color, rect)
        light = tuple(min(255, c + 60) for c in color)
        dark = tuple(max(0, c - 70) for c in color)
        pygame.draw.line(self.screen, light, rect.topleft, rect.topright)
        pygame.draw.line(self.screen, light, rect.topleft, rect.bottomleft)
        pygame.draw.line(self.screen, dark, rect.bottomleft, rect.bottomright)
        pygame.draw.line(self.screen, dark, rect.topright, rect.bottomright)
        pygame.draw.rect(self.screen, (10, 10, 14), rect, 1)

    def draw(self, game):
        self.screen.fill(BG_COLOR)
        board_rect = pygame.Rect(BOARD_X, BOARD_Y, BOARD_W, BOARD_H)
        pygame.draw.rect(self.screen, (12, 12, 18), board_rect)

        for y in range(ROWS):
            for x in range(COLS):
                color = game.board[y][x]
                if color is not None:
                    blinking = (y in game.clearing_rows and
                                (game.clear_timer // 120) % 2 == 0)
                    if blinking:
                        color = (255, 255, 255)
                    self.draw_block(BOARD_X + x * CELL, BOARD_Y + y * CELL,
                                    color)

        for gx in range(COLS + 1):
            px = BOARD_X + gx * CELL
            pygame.draw.line(self.screen, GRID_COLOR, (px, BOARD_Y),
                             (px, BOARD_Y + BOARD_H))
        for gy in range(ROWS + 1):
            py = BOARD_Y + gy * CELL
            pygame.draw.line(self.screen, GRID_COLOR, (BOARD_X, py),
                             (BOARD_X + BOARD_W, py))
        pygame.draw.rect(self.screen, BORDER_COLOR, board_rect, 2)

        if game.current is not None and not game.clearing_rows:
            for (x, y) in game.current.absolute_cells():
                if y >= 0:
                    self.draw_block(BOARD_X + x * CELL, BOARD_Y + y * CELL,
                                    game.current.color)

        self._draw_panel(game)

        if game.paused or game.game_over:
            self._draw_overlay(game)

        pygame.display.flip()

    def _draw_panel(self, game):
        px = BOARD_X + BOARD_W + 20
        panel_rect = pygame.Rect(px - 10, BOARD_Y, PANEL_W - 10, BOARD_H)
        pygame.draw.rect(self.screen, PANEL_COLOR, panel_rect, border_radius=8)

        self.screen.blit(self.font_med.render("SCORE", True, DIM_COLOR),
                         (px + 10, BOARD_Y + 15))
        self.screen.blit(self.font_big.render(str(game.score), True, TEXT_COLOR),
                         (px + 10, BOARD_Y + 42))

        self.screen.blit(self.font_med.render("NEXT", True, DIM_COLOR),
                         (px + 10, BOARD_Y + 100))
        preview = Piece(game.next_kind)
        cells = preview.cells
        min_x = min(cx for (cx, _) in cells)
        max_x = max(cx for (cx, _) in cells)
        min_y = min(cy for (_, cy) in cells)
        max_y = max(cy for (_, cy) in cells)
        w = (max_x - min_x + 1) * CELL
        h = (max_y - min_y + 1) * CELL
        ox = px + 10 + (4 * CELL - w) // 2 - min_x * CELL
        oy = BOARD_Y + 132 + (2 * CELL - h) // 2 - min_y * CELL
        pygame.draw.rect(self.screen, (20, 20, 28),
                         (px + 8, BOARD_Y + 130, 4 * CELL + 4, 2 * CELL + 4),
                         border_radius=4)
        for (cx, cy) in cells:
            self.draw_block(ox + cx * CELL, oy + cy * CELL, preview.color,
                            CELL)

        controls = [
            "CONTROLS",
            "",
            "Left/Right  Move",
            "Down        Soft drop",
            "Up          Rotate",
            "Space       Hard drop",
            "P           Pause",
            "R           Restart",
            "Esc         Quit",
        ]
        cy = BOARD_Y + 230
        for i, line in enumerate(controls):
            font = self.font_med if i == 0 else self.font_small
            color = DIM_COLOR if i == 0 else TEXT_COLOR
            self.screen.blit(font.render(line, True, color), (px + 10, cy))
            cy += 26 if i == 0 else 22

    def _draw_overlay(self, game):
        overlay = pygame.Surface((SCREEN_W, SCREEN_H), pygame.SRCALPHA)
        overlay.fill(OVERLAY_COLOR)
        self.screen.blit(overlay, (0, 0))
        if game.game_over:
            title = self.font_big.render("GAME OVER", True, (255, 90, 90))
            score = self.font_med.render(f"Final Score: {game.score}", True,
                                         TEXT_COLOR)
            hint = self.font_small.render("Press R to restart, Esc to quit",
                                          True, DIM_COLOR)
        else:
            title = self.font_big.render("PAUSED", True, TEXT_COLOR)
            score = self.font_small.render("Press P to resume", True, DIM_COLOR)
            hint = None
        cx = SCREEN_W // 2
        cy = SCREEN_H // 2
        self.screen.blit(title, title.get_rect(center=(cx, cy - 40)))
        self.screen.blit(score, score.get_rect(center=(cx, cy + 5)))
        if hint:
            self.screen.blit(hint, hint.get_rect(center=(cx, cy + 45)))


def main():
    pygame.init()
    screen = pygame.display.set_mode((SCREEN_W, SCREEN_H))
    pygame.display.set_caption("Tetris")
    clock = pygame.time.Clock()
    game = Game()
    renderer = Renderer(screen)

    running = True
    while running:
        dt = clock.tick(FPS)
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False
            elif event.type == pygame.KEYDOWN:
                if event.key == pygame.K_ESCAPE:
                    running = False
                elif event.key == pygame.K_r:
                    game.reset()
                elif event.key == pygame.K_p:
                    if not game.game_over:
                        game.paused = not game.paused
                elif game.game_over or game.paused:
                    pass
                elif event.key == pygame.K_LEFT:
                    game.move(-1, 0)
                elif event.key == pygame.K_RIGHT:
                    game.move(1, 0)
                elif event.key == pygame.K_DOWN:
                    game.soft_drop()
                elif event.key == pygame.K_UP:
                    game.rotate()
                elif event.key == pygame.K_SPACE:
                    game.hard_drop()

        game.update(dt)
        renderer.draw(game)

    pygame.quit()
    sys.exit()


if __name__ == "__main__":
    main()
