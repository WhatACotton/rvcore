// Minimal cf_math_pkg for APB interface compatibility
// Contains only the ceil_div function needed by apb_intf.sv

package cf_math_pkg;

  // Calculate ceiling of division (divides a by b and rounds up)
  function automatic integer ceil_div(input integer a, input integer b);
    return (a + b - 1) / b;
  endfunction

endpackage
