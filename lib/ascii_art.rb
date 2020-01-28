
module NMEAPlusGoogleEarth

  # A class to render boats in the terminal
  #
  # boat(1, 1, 1, 0.1, "DINGHY")
  #    ___    DINGHY
  # ~~~\\/~~~~~~~~~~
  #
  # boat(4, 2, 1, 0.8, "TUG")
  #    ___]T[_    TUG
  # ~~~\___\_/~~~~~~~
  #
  # boat(18, 4, 3, 0.1, "TANKER")
  #    _]TTT[_________________
  # ~~~|          TANKER |   |~~~
  #    |                 |   |
  #    \_________________\___/
  #
  class AsciiArt

    WATER_PAD = 3  # how much water is on the side
    LABEL_DISTANCE = WATER_PAD + 1  # how far the label is from the ship, when it can't fit on the side

    # helper function to get the fluid (air or water) art for left and right of a boat drawing
    def self._fluid(did_water, label, label_on_ship)
      fl = (did_water ? " " : "~") * WATER_PAD
      fr = did_water ? "" : ("~" * (WATER_PAD + (label_on_ship ? 0 : label.length + 1)))
      return fl, fr
    end

    # draws a boat with a given length, width, and draft (minimum of 1 each)
    # the tower position is a decimal ratio (range 0..1) of where over the length the tower should be drawn
    # the label is optional -- the boat name will be printed on the boat if there's room, or floating
    # in the sky next to it if there isn't room.
    def self.boat(length, width, draft, tower_position, lbl="")
      l = [1, length.to_f.ceil].max
      w = [1, width.to_f.ceil].max
      h = [1, draft.to_f.ceil].max
      label = lbl.to_s

      ret = []
      lt = (l + w + 1)
      la = l - 1
      wa = w - 1
      lu = "_" * la
      wu = "_" * wa
      ls = " " * la
      ws = " " * wa

      # draw the top of the ship, with a tower that displays width and position
      top = "_" * lt
      tower_idx = (tower_position * (l + 1) * 0.99).floor
      case
      when lt < 4 && l < 3
        top[tower_idx] = "_"  # this is a no-op.  I can't find a good small tower.
      when w < 2
        top[tower_idx] = "I"
      else
        top[tower_idx] = "]"
        top[tower_idx + w] = "["
        for i in (tower_idx + 1)..(tower_idx + w - 1)
          top[i] = "T"
        end
      end

      # if the ship name is longer than the ship, display it in the air
      label_on_ship = h > 1 && (la - label.length) > 1
      if !label_on_ship
        top << (" " * LABEL_DISTANCE) + label
      end

      ret << (" " * WATER_PAD) + top

      # make the sides of the ship
      did_name = false
      did_water = false
      (h - 1).times do
        # fluid left and right
        fl, fr = _fluid(did_water, label, label_on_ship)
        if did_name || (la - label.length < 2)
          ret << "#{fl}|#{ls}|#{ws}|#{fr}"
        else
          prf = " " * (la - (label.length + 1))
          ret << "#{fl}|#{prf}#{label} |#{ws}|#{fr}"
          did_name = true
        end
        did_water = true
      end

      # make the bottom of the ship
      fl, fr = _fluid(did_water, label, label_on_ship)
      ret << "#{fl}\\#{lu}\\#{wu}/#{fr}"
      ret.join("\n")
    end

  end
end
