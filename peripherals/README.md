# Peripherals

APB-bus peripherals for the rv32i RV32I SoC.

## Available Peripherals

| Peripheral | Directory | Description |
|-----------|-----------|-------------|
| **GPIO** | `gpio/` | 32-bit general-purpose I/O with edge interrupts |
| **Timer** | `timer/` | 32-bit timer/counter with prescaler and compare-match |
| **SPI Master** | `spi_master/` | APB SPI master controller |

---

## GPIO (`peripherals/gpio/apb_gpio.v`)

32-bit GPIO with APB slave interface.

**Register Map:**

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| `0x00` | `GPIO_DIR` | R/W | Pin direction (0=input, 1=output) |
| `0x04` | `GPIO_OUT` | R/W | Output data |
| `0x08` | `GPIO_IN` | R | Input data (sampled, read-only) |
| `0x0C` | `GPIO_IRQ_EN` | R/W | Interrupt enable per pin |
| `0x10` | `GPIO_IRQ_FLAG` | R/W1C | Interrupt flags (write 1 to clear) |
| `0x14` | `GPIO_IRQ_EDGE` | R/W | Edge select (0=rising, 1=falling) |

**Features:**
- 2-stage input synchronizer
- Per-pin rising/falling edge interrupt
- Active-high output enable for tri-state pads

---

## Timer (`peripherals/timer/apb_timer.v`)

32-bit timer/counter with APB slave interface.

**Register Map:**

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| `0x00` | `TIMER_CTRL` | R/W | Control: `[0]` EN, `[1]` IRQ_EN, `[2]` ONE_SHOT, `[3]` OVF_EN |
| `0x04` | `TIMER_COUNT` | R/W | Current counter value |
| `0x08` | `TIMER_CMP` | R/W | Compare value (match → interrupt) |
| `0x0C` | `TIMER_PSC` | R/W | Prescaler (counter ticks every PSC+1 clocks) |
| `0x10` | `TIMER_STATUS` | R/W1C | Flags: `[0]` MATCH, `[1]` OVF |

**Features:**
- Configurable prescaler (divide clock by 1 to 2^32)
- Compare-match and overflow interrupts
- One-shot mode (auto-stop on match) or continuous mode

---

## SPI Master (`peripherals/spi_master/`)

APB SPI master controller (existing IP). See the `spi_master/` subdirectory for full source and documentation.

---

## Integration Notes

All peripherals use the **APB (Advanced Peripheral Bus)** interface:
- Single-cycle access, `pready_o` always asserted
- Active-low asynchronous reset (`rst_n`)
- Address decoding should be done at the SoC interconnect level

To add a peripheral to the SoC:
1. Instantiate it in `rtl/soc/top_soc.v`
2. Add APB address decode logic to map a base address
3. Connect `irq_o` to the core's interrupt controller
