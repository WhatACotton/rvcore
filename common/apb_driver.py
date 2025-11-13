from typing import Tuple


class APBMaster:
    def __init__(self, dut, prefix: str, clk):
        self.dut = dut
        self.prefix = prefix.rstrip('_')
        self.clk = clk

        # Construct attribute names
        def s(name):
            return f"{self.prefix}_{name}"

        # Helper to try multiple candidate names for a signal
        def find_signal(base_name):
            candidates = [
                s(base_name),
                f"o_{self.prefix}_{base_name}",
                f"{self.prefix.replace('i_', 'o_')}_{base_name}",
            ]
            for name in candidates:
                try:
                    return getattr(dut, name)
                except AttributeError:
                    continue
            # Try without prefix (rare)
            try:
                return getattr(dut, base_name)
            except AttributeError:
                pass

            # Last-ditch: search one level deep in DUT hierarchy for matching signals.
            # This helps when APB signals are instantiated inside a submodule.
            for attr in dir(dut):
                if attr.startswith('_'):
                    continue
                try:
                    child = getattr(dut, attr)
                except Exception:
                    continue
                for name in candidates + [base_name]:
                    try:
                        sig = getattr(child, name)
                        return sig
                    except Exception:
                        continue

            raise AttributeError(f"No APB signal found for {base_name}; tried: {candidates} and nested attrs")

        def find_name(base_name):
            """Return the first matching signal name for debugging purposes."""
            candidates = [
                s(base_name),
                f"o_{self.prefix}_{base_name}",
                f"{self.prefix.replace('i_', 'o_')}_{base_name}",
            ]
            for name in candidates:
                if hasattr(dut, name):
                    return name
            if hasattr(dut, base_name):
                return base_name
            # Search one level deep and return the resolved "parent.name" pattern
            for attr in dir(dut):
                if attr.startswith('_'):
                    continue
                try:
                    child = getattr(dut, attr)
                except Exception:
                    continue
                for name in candidates + [base_name]:
                    if hasattr(child, name):
                        return f"{attr}.{name}"
            return None

        # Required APB signals
        self.paddr = find_signal('paddr')
        self.psel = find_signal('psel')
        self.penable = find_signal('penable')
        self.pwrite = find_signal('pwrite')
        self.pwdata = find_signal('pwdata')
        # pready/prdata/pslverr may be outputs from DUT with different prefixes
        self.pready = find_signal('pready')
        self.prdata = find_signal('prdata')
        # pslverr is optional - return None if not present
        try:
            self.pslverr = find_signal('pslverr')
        except AttributeError:
            self.pslverr = None

        # Record resolved signal names for easier debugging
        try:
            self._names = {
                'paddr': find_name('paddr'),
                'psel': find_name('psel'),
                'penable': find_name('penable'),
                'pwrite': find_name('pwrite'),
                'pwdata': find_name('pwdata'),
                'pready': find_name('pready'),
                'prdata': find_name('prdata'),
                'pslverr': find_name('pslverr'),
            }
        except Exception:
            self._names = {}

        # Log resolved names at debug level
        try:
            dut_log = getattr(dut, '_log', None)
            if dut_log is not None:
                # Log at INFO so it's visible in default test logs
                dut_log.info(f"APBMaster bound signals: {self._names}")
        except Exception:
            pass

    async def write(self, addr: int, data: int) -> Tuple[bool, str]:
        """Perform an APB write transaction.

        Returns (True, None) on success, (False, error_str) on failure.
        """
        # Drive address and data
        dut_log = getattr(self.dut, '_log', None)
        if dut_log is not None:
            try:
                dut_log.info(f"APB write: addr=0x{addr:08X} data=0x{data:08X} bindings={self._names}")
            except Exception:
                dut_log.info("APB write (bindings info unavailable)")

        # Try to drive signals and log before/after to ensure they change
        try:
            self.paddr.value = addr
            self.pwdata.value = data
            self.pwrite.value = 1
            self.psel.value = 1
            self.penable.value = 0
        except Exception as e:
            if dut_log is not None:
                dut_log.error(f"Failed to drive APB signals: {e}")
            raise

        # One cycle before enable
        await self._clk_cycle()

        # Log signal snapshot before enabling
        if dut_log is not None:
            try:
                dut_log.debug(f"APB before penable: psel={int(self.psel.value)} penable={int(self.penable.value)} pwrite={int(self.pwrite.value)} paddr=0x{int(self.paddr.value):08X}")
            except Exception:
                pass

        # Assert penable
        self.penable.value = 1

        # Log after asserting penable
        if dut_log is not None:
            try:
                dut_log.debug(f"APB after penable: psel={int(self.psel.value)} penable={int(self.penable.value)} pwrite={int(self.pwrite.value)} paddr=0x{int(self.paddr.value):08X}")
            except Exception:
                pass

        await self._wait_pready()

        # Deassert
        self.psel.value = 0
        self.penable.value = 0
        self.pwrite.value = 0

        # Check pslverr if available
        if self.pslverr is not None and int(self.pslverr.value) == 1:
            return False, 'pslverr asserted'

        return True, None

    async def read(self, addr: int) -> Tuple[int, str]:
        """Perform an APB read transaction.

        Returns (value, None) on success or (0, error_str) on failure.
        """
        self.paddr.value = addr
        self.pwrite.value = 0
        self.psel.value = 1
        self.penable.value = 0

        await self._clk_cycle()

        self.penable.value = 1
        await self._wait_pready()

        # Capture data
        val = int(self.prdata.value)

        # Deassert
        self.psel.value = 0
        self.penable.value = 0

        if self.pslverr is not None and int(self.pslverr.value) == 1:
            return 0, 'pslverr asserted'

        return val, None

    async def _wait_pready(self):
        # Wait until pready is asserted (with a timeout to avoid hangs)
        # Provide helpful debug output to diagnose bus issues.
        dut_log = getattr(self.dut, '_log', None)
        max_cycles = 5000
        for cycle in range(max_cycles):
            try:
                pv = int(self.pready.value)
            except Exception:
                pv = None
            if dut_log is not None and (cycle % 500) == 0:
                dut_log.debug(f"APB wait_pready cycle={cycle} psel={int(self.psel.value)} penable={int(self.penable.value)} pwrite={int(self.pwrite.value)} pready={pv}")
            if pv == 1:
                # wait one cycle for data to stabilize
                await self._clk_cycle()
                return
            await self._clk_cycle()
        # Dump final state for debugging before raising
        if dut_log is not None:
            try:
                dut_log.error(f"APB pready timeout after {max_cycles} cycles: psel={int(self.psel.value)} penable={int(self.penable.value)} pwrite={int(self.pwrite.value)} pready={int(self.pready.value)} paddr=0x{int(self.paddr.value):08X}")
            except Exception:
                dut_log.error("APB pready timeout (could not read signal values)")
        raise TimeoutError('APB pready timeout')

    async def _clk_cycle(self):
        # Helper: wait 1 clock cycle
        from cocotb.triggers import RisingEdge
        await RisingEdge(self.clk)
