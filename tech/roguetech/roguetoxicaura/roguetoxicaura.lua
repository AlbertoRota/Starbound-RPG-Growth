require "/tech/doubletap.lua"
require "/scripts/keybinds.lua"

function init()
  self.airDashing = false
  self.dashDirection = 0
  self.dashTimer = 0
  self.dashCooldownTimer = 0
  self.rechargeEffectTimer = 0
  self.auraRechargeEffectTimer = 0

  self.dashControlForce = config.getParameter("dashControlForce")
  self.dashSpeed = config.getParameter("dashSpeed")
  self.dashDuration = config.getParameter("dashDuration")
  self.dashCooldown = config.getParameter("dashCooldown")
  self.groundOnly = config.getParameter("groundOnly")
  self.stopAfterDash = config.getParameter("stopAfterDash")

  self.rechargeDirectives = config.getParameter("rechargeDirectives", "?fade=25492EFF=0.25")
  self.rechargeEffectTime = config.getParameter("rechargeEffectTime", 0.1)

  self.auraRechargeDirectives = config.getParameter("rechargeDirectives", "?fade=89A04EFF=0.25")
  self.auraRechargeEffectTime = config.getParameter("rechargeEffectTime", 0.1)

  self.cooldownTimer = 0
  self.cooldown = config.getParameter("cooldown")
  self.duration = config.getParameter("duration")
  self.cooldownActive = false

  self.doubleTap = DoubleTap:new({"left", "right"}, config.getParameter("maximumDoubleTapTime"), function(dashKey)
      if self.dashTimer == 0
          and self.dashCooldownTimer == 0
          and groundValid()
          and not mcontroller.crouching()
          and not status.statPositive("activeMovementAbilities") then

        startDash(dashKey == "left" and -1 or 1)
      end
    end)
  Bind.create("g", toxicAura)
  animator.setAnimationState("dashing", "off")
end

function uninit()
  status.clearPersistentEffects("movementAbility")
  status.removeEphemeralEffect("rtoxicaura")
  status.removeEphemeralEffect("roguetoxicauracooldown")
  deactivateAura()
  tech.setParentDirectives()
end

function toxicAura()
  if self.cooldownTimer <= 0 then
    self.cooldownTimer = self.cooldown + self.duration
    status.addEphemeralEffect("rtoxicaura", self.duration)
    activateAura()
  end
end

function update(args)

  if self.cooldownTimer > 0 then
    self.cooldownTimer = math.max(0, self.cooldownTimer - args.dt)
    if self.cooldownTimer == 0 then
      self.cooldownActive = false
      self.auraRechargeEffectTimer = self.auraRechargeEffectTime
      tech.setParentDirectives(self.auraRechargeDirectives)
      animator.playSound("recharge")
    elseif self.cooldownTimer <= self.cooldown and not self.cooldownActive then
      self.cooldownActive = true
      status.addEphemeralEffect("roguetoxicauracooldown", self.cooldownTimer)
    end
  end

  if self.auraRechargeEffectTimer > 0 then
    self.auraRechargeEffectTimer = math.max(0, self.auraRechargeEffectTimer - args.dt)
    if self.auraRechargeEffectTimer == 0 then
      tech.setParentDirectives()
    end
  end

  if self.dashCooldownTimer > 0 then
    self.dashCooldownTimer = math.max(0, self.dashCooldownTimer - args.dt)
    if self.dashCooldownTimer == 0 then
      self.rechargeEffectTimer = self.rechargeEffectTime
      tech.setParentDirectives(self.rechargeDirectives)
      animator.playSound("recharge")
    end
  end

  if self.rechargeEffectTimer > 0 then
    self.rechargeEffectTimer = math.max(0, self.rechargeEffectTimer - args.dt)
    if self.rechargeEffectTimer == 0 then
      tech.setParentDirectives()
    end
  end

  self.doubleTap:update(args.dt, args.moves)

  if self.dashTimer > 0 then
    mcontroller.controlApproachVelocity({self.dashSpeed * self.dashDirection, 0}, self.dashControlForce)
    mcontroller.controlMove(self.dashDirection, true)

    self.power = status.stat("powerMultiplier")
    self.poison = status.stat("poisonResistance")
    self.poison = self.poison >= .1 and self.poison or (self.poison >= 1 and 5 or .1)
    self.poison = status.statPositive("poisonStatusImmunity") and 5 or self.poison

    self.damageConfig = {
      power = self.power*self.poison*10
    }
    world.spawnProjectile("poisontrail", {mcontroller.xPosition(), mcontroller.yPosition()-2}, entity.id(), {0,0}, false, self.damageConfig)

    if self.airDashing then
      mcontroller.setYVelocity(0)
    end
    mcontroller.controlModifiers({jumpingSuppressed = true})

    animator.setFlipped(mcontroller.facingDirection() == -1)

    self.dashTimer = math.max(0, self.dashTimer - args.dt)

    if self.dashTimer == 0 then
      endDash()
    end
  end
end

function groundValid()
  return mcontroller.groundMovement() or not self.groundOnly
end

function startDash(direction)
  self.dashDirection = direction
  self.dashTimer = self.dashDuration
  self.airDashing = not mcontroller.groundMovement()
  status.setPersistentEffects("movementAbility", {{stat = "activeMovementAbilities", amount = 1}})
  animator.playSound("startDash")
  animator.setAnimationState("dashing", "on")
  animator.setParticleEmitterActive("dashParticles", true)
end

function endDash()
  status.clearPersistentEffects("movementAbility")

  if self.stopAfterDash then
    local movementParams = mcontroller.baseParameters()
    local currentVelocity = mcontroller.velocity()
    if math.abs(currentVelocity[1]) > movementParams.runSpeed then
      mcontroller.setVelocity({movementParams.runSpeed * self.dashDirection, 0})
    end
    mcontroller.controlApproachXVelocity(self.dashDirection * movementParams.runSpeed, self.dashControlForce)
  end

  self.dashCooldownTimer = self.dashCooldown

  animator.setAnimationState("dashing", "off")
  animator.setParticleEmitterActive("dashParticles", false)
end

function activateAura()
    if not self.aura then
      self.timeConfig = {
        timeToLive = self.duration
      }
      self.aura = world.spawnProjectile("rtoxicaura",
                                            mcontroller.position(),
                                            entity.id(),
                                            {0,0},
                                            true,
                                            self.timeConfig
                                           )
    end
end

function deactivateAura()
    if self.aura then
      world.entityQuery(mcontroller.position(),1,
        {
         withoutEntityId = entity.id(),
         includedTypes = {"projectile"},
         callScript = "removeAura",
         callScriptArgs = {self.aura}
        }
      )
      self.aura = nil
    end
end